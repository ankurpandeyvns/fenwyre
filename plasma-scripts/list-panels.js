var o=[];panels().forEach(function(p){o.push("panel "+p.id+" screen "+p.screen+" loc "+p.location+": "+p.widgets().map(function(w){return w.id+":"+w.type}).join(", "))});print(o.join("\n"));
