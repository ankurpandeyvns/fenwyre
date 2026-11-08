// SPDX-License-Identifier: MIT
/*
 * ddc-coalesce: LD_PRELOAD for PowerDevil (libddcutil) that coalesces DDC/CI
 * brightness writes.
 *
 * PowerDevil sends every intermediate value of a slider drag or held brightness
 * key to the monitor, one DDC/CI write after another. Behind a slow link (the
 * MacBook's HDMI port goes through a DP->HDMI converter, ~0.2 s a write) the
 * monitor then lags seconds behind the slider. Here a brightness write
 * (VCP 0x10) only records the value and returns; one thread per display sends
 * the newest value, so values superseded meanwhile are never sent. Other
 * features pass straight through. ddca_close_display() first lets that
 * display's writer send the newest value, so handles are never used after
 * they are closed and the last value is not lost.
 *
 * Build: cc -O2 -shared -fPIC -o libddc-coalesce.so ddc-coalesce.c -ldl -lpthread
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <ddcutil_c_api.h>
#include <ddcutil_status_codes.h>

#define VCP_BRIGHTNESS 0x10
#define SLOTS 16

typedef DDCA_Status (*set_fn)(DDCA_Display_Handle, DDCA_Vcp_Feature_Code, uint8_t, uint8_t);
typedef DDCA_Status (*close_fn)(DDCA_Display_Handle);

struct slot {
	DDCA_Display_Handle dh;
	uint8_t hi, lo;
	bool pending, busy, running, closing;
	pthread_cond_t cond;		/* pending, or closing */
	pthread_cond_t idle;		/* !busy */
};

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static struct slot slots[SLOTS];
static set_fn real_set;
static close_fn real_close;

static void resolve(void)
{
	if (!real_set)
		real_set = (set_fn)dlsym(RTLD_NEXT, "ddca_set_non_table_vcp_value");
	if (!real_close)
		real_close = (close_fn)dlsym(RTLD_NEXT, "ddca_close_display");
}

static void *writer(void *arg)
{
	struct slot *s = arg;

	pthread_mutex_lock(&lock);
	for (;;) {
		while (!s->pending && !s->closing)
			pthread_cond_wait(&s->cond, &lock);
		if (!s->pending)	/* closing, nothing left to send */
			break;
		DDCA_Display_Handle dh = s->dh;
		uint8_t hi = s->hi, lo = s->lo;

		s->pending = false;
		s->busy = true;
		pthread_mutex_unlock(&lock);
		DDCA_Status rc = real_set(dh, VCP_BRIGHTNESS, hi, lo);
		if (rc)
			fprintf(stderr, "ddc-coalesce: brightness %u failed: %d\n", (hi << 8) | lo, rc);
		pthread_mutex_lock(&lock);
		s->busy = false;
		pthread_cond_broadcast(&s->idle);
	}
	s->running = false;
	s->closing = false;
	s->dh = NULL;
	pthread_cond_broadcast(&s->idle);
	pthread_mutex_unlock(&lock);
	return NULL;
}

static struct slot *find(DDCA_Display_Handle dh, bool create)
{
	struct slot *free_slot = NULL;

	for (int i = 0; i < SLOTS; i++) {
		if (slots[i].dh == dh && slots[i].running)
			return &slots[i];
		if (!slots[i].running && !free_slot)
			free_slot = &slots[i];
	}
	if (!create || !free_slot)
		return NULL;
	pthread_cond_init(&free_slot->cond, NULL);
	pthread_cond_init(&free_slot->idle, NULL);
	free_slot->dh = dh;
	free_slot->pending = free_slot->busy = free_slot->closing = false;
	free_slot->running = true;
	pthread_t t;
	if (pthread_create(&t, NULL, writer, free_slot)) {
		free_slot->running = false;
		free_slot->dh = NULL;
		return NULL;
	}
	pthread_detach(t);
	return free_slot;
}

DDCA_Status ddca_set_non_table_vcp_value(DDCA_Display_Handle dh, DDCA_Vcp_Feature_Code code,
					 uint8_t hi, uint8_t lo)
{
	resolve();
	if (code != VCP_BRIGHTNESS || !real_set)
		return real_set ? real_set(dh, code, hi, lo) : DDCRC_ARG;
	pthread_mutex_lock(&lock);
	struct slot *s = find(dh, true);
	if (!s || s->closing) {		/* no slot or thread: write synchronously */
		pthread_mutex_unlock(&lock);
		return real_set(dh, code, hi, lo);
	}
	s->hi = hi;
	s->lo = lo;
	s->pending = true;
	pthread_cond_signal(&s->cond);
	pthread_mutex_unlock(&lock);
	return 0;
}

DDCA_Status ddca_close_display(DDCA_Display_Handle dh)
{
	resolve();
	pthread_mutex_lock(&lock);
	struct slot *s = find(dh, false);
	if (s) {
		s->closing = true;	/* the writer sends what is pending, then exits */
		pthread_cond_signal(&s->cond);
		while (s->running)	/* the writer finishes its write, then exits */
			pthread_cond_wait(&s->idle, &lock);
	}
	pthread_mutex_unlock(&lock);
	return real_close ? real_close(dh) : DDCRC_ARG;
}
