# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide at https://www.varnish-cache.org/docs/
# and http://varnish-cache.org/trac/wiki/VCLExamples for more examples.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

import std;

# Default backend definition. Set this to point to your content server.

backend default {
   .host = "127.0.0.1";
   .port = "8080";

#  .max_connections = 250;     # Set the maximum number of connections for backend
   .connect_timeout = 300s;
   .first_byte_timeout = 300s;
   .between_bytes_timeout = 300s;


   .probe = {
#  .url = "/"; # short easy way (GET /)
# We prefer to only do a HEAD /
   .url = "/ReleaseNote.txt";
   .interval  = 5s; # check the health of each backend every 5 seconds
   .timeout   = 1s; # timing out after 1 second.
   .window    = 5;  # If 3 out of the last 5 polls succeeded the backend is considered healthy, otherwise it will be marked as sick
   .threshold = 3;
  }



}


acl purge {
  # ACL we'll use later to allow purges
  "localhost";
  "127.0.0.1";
  "::1";
}

sub vcl_recv {
  # Happens before we check if we have this in cache already.
  # Typically you clean up the request here, removing cookies you don't need,
  # rewriting the request, etc.
  # Don't check cache if the Drupal session cookie is set.
  # Pressflow pages don't send this cookie to anon users.  
  if(req.http.cookie ~ "(^|;\s*)(S?SESS[a-zA-Z0-9]*)=") {
    return(pass);
  }
  # To See the contents of header and debug
  # return (synth(405, req.http.Cookie));

  # Cookie Cache Bypass Drupal module (Pressflow): Don't check cache for
  # any user that just submitted a content form within the past 5 to 10
  # minutes (depending on Drupal's cache_lifetime setting).
  # Persistent login module support: http://drupal.org/node/1306214
  if(req.http.cookie ~ "(NO_CACHE|PERSISTENT_LOGIN_[a-zA-Z0-9]+)") {
    return(pass);
  }

  unset req.http.Cookie;
  # Pipe all requests for files whose Content-Length is >=10,000,000. See
  # comment in vcl_fetch.

  if (req.http.x-pipe && req.restarts > 0) {
    return(pipe);
  }

  # Varnish doesn't support Range requests: needs to be piped
  if (req.http.Range) {
    return(pipe);
  }
  # Diverting requets from ip to an error page as it directs to install.php.
  #if (req.url ~ "^/install.php"){
  #   return (synth(403, "Access Denied. Please connect with Capgemini DevOps for Support."));
  # }



  # Don't Cache executables or archives
  # This was put in place to ensure these objects are piped rather then passed to the backend.
  # We had a customer who had a 500+MB file *.msi that Varnish was choking on,
  # so we decided to pipe all archives and executables to keep them from choking Varnish.
  if(req.url ~ "\.(msi|exe|dmg|zip|tgz|gz)") {
    return(pipe);
  }
   

  if (req.restarts == 0) {
    if (req.http.X-Forwarded-For) { # set or append the client.ip to X-Forwarded-For header
      set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
    } else {
      set req.http.X-Forwarded-For = client.ip;
    }
  }

  #Normalize the header, remove the port (in case you're testing this on various TCP ports)
  set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");


  # Normalize the query arguments
  set req.url = std.querysort(req.url);

  # Only deal with "normal" types
  if (req.method != "GET" &&
      req.method != "HEAD" &&
      req.method != "PUT" &&
      req.method != "TRACE" &&
      req.method != "OPTIONS" &&
      req.method != "PATCH" &&
      req.method != "DELETE") {
    /* Non-RFC2616 or CONNECT which is weird. */
    return (pipe);

  }

  # Do not cache these paths.
  if (req.url ~ "^/status\.php$" ||
    req.url ~ "^/update\.php$" ||
    req.url ~ "^/ooyala/ping$" ||
    req.url ~ "^/admin/build/features" ||
    req.url ~ "^/info/.*$" ||
    req.url ~ "^/flag/.*$" ||
    req.url ~ "^.*/ajax/.*$" ||
    req.url ~ "^.*/ahah/.*$") {
     return (pass);
  }

  # Force look-up if request is a no-cache request.
    if (req.http.Cache-Control ~ "no-cache")
    {
        return (hash);
    }


  # Some generic URL manipulation, useful for all templates that follow
  # First remove the Google Analytics added parameters, useless for our backend
  if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=") {
    set req.url = regsuball(req.url, "&(utm_source|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
    set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
    set req.url = regsub(req.url, "\?&", "?");
    set req.url = regsub(req.url, "\?$", "");
  }

  # Some generic cookie manipulation, useful for all templates that follow
  # Remove the "has_js" cookie
  set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");

  # Remove any Google Analytics based cookies
  set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "_gat=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd.=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "utmccn.=[^;]+(; )?", "");



  # Remove DoubleClick offensive cookies
  set req.http.Cookie = regsuball(req.http.Cookie, "__gads=[^;]+(; )?", "");

  # Remove the Quant Capital cookies (added by some plugin, all __qca)
  set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

  # Remove the AddThis cookies
  set req.http.Cookie = regsuball(req.http.Cookie, "__atuv.=[^;]+(; )?", "");

  # Remove a ";" prefix in the cookie if present
  set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

  # Normalize Accept-Encoding header
  # straight from the manual: https://www.varnish-cache.org/docs/3.0/tutorial/vary.html
  # TODO: Test if it's still needed, Varnish 4 now does this by itself if http_gzip_support = on
  # https://www.varnish-cache.org/docs/trunk/users-guide/compression.html
  # https://www.varnish-cache.org/docs/trunk/phk/gzip.html
  if (req.http.Accept-Encoding) {
    if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
      # No point in compressing these
     unset req.http.Accept-Encoding;
    } elsif (req.http.Accept-Encoding ~ "gzip") {
      set req.http.Accept-Encoding = "gzip";
    } elsif (req.http.Accept-Encoding ~ "deflate") {
     set req.http.Accept-Encoding = "deflate";
    } else {
      # unkown algorithm
      unset req.http.Accept-Encoding;
    }
  }
  
  # Allow ban
  if (req.method == "BAN") {
                # Same ACL check as above:
                if (!client.ip ~ purge) {
                        return(synth(403, "Not allowed."));
                }
                # ban("req.http.host == " + req.http.host +
                     # " && req.url == " + req.url);
                   ban("obj.http.url ~ " + req.url); # Assumes req.url is a regex. This might be a bit too simple
                # Throw a synthetic page so the
                # request won't go to the backend.
                return(synth(200, "Ban added"));
  }
  
  # Allow purging
  if (req.method == "PURGE") {
  	if (!client.ip ~ purge) { # purge is the ACL defined at the begining
      		# Not from an allowed IP? Then die with an error.
      		return (synth(405, "This IP is not allowed to send PURGE requests."));
    	}
    # If you got this stage (and didn't error out above), purge the cached result
    	return (purge);
  }
  
  ## Unset Authorization header if it has the correct details...(This should be enabled in the varnish config when there is authentication requirement.)
  if (req.http.Authorization == "Basic ") {
   unset req.http.Authorization;
  }

  return (hash);


}
sub vcl_hash {
  # Called after vcl_recv to create a hash value for the request. This is used as a key
  # to look up the object in Varnish.
     hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    return (lookup);                           

}
sub vcl_miss {
  # Called after a cache lookup if the requested document was not found in the cache. Its purpose
  # is to decide whether or not to attempt to retrieve the document from the backend, and which
  # backend to use.
  return (fetch);
}



sub vcl_pipe {
  set req.http.connection = "close";
}


sub vcl_hit {
  # Called when a cache lookup is successful.

  if (obj.ttl >= 0s) {
    # A pure unadultered hit, deliver it
    return (deliver);
  }

# https://www.varnish-cache.org/docs/trunk/users-guide/vcl-grace.html
# When several clients are requesting the same page Varnish will send one request to the backend and place the others on hold while fetching one copy from the backend. In some products this is called request coalescing and Varnish does this automatically.
# If you are serving thousands of hits per second the queue of waiting requests can get huge. There are two potential problems - one is a thundering herd problem - suddenly releasing a thousand threads to serve content might send the load sky high. Secondly - nobody likes to wait. To deal with this we can instruct Varnish to keep the objects in cache beyond their TTL and to serve the waiting requests somewhat stale content.

# if (!std.healthy(req.backend_hint) && (obj.ttl + obj.grace > 0s)) {
#   return (deliver);
# } else {
#   return (fetch);
# }

# We have no fresh fish. Lets look at the stale ones.
  if (std.healthy(req.backend_hint)) {
    # Backend is healthy. Limit age to 10s.
    if (obj.ttl + 10s > 0s) {
      #set req.http.grace = "normal(limited)";
      return (deliver);
    } else {
      # No candidate for grace. Fetch a fresh object.
      return(fetch);
    }
  } else {
    # backend is sick - use full grace
      if (obj.ttl + obj.grace > 0s) {
      #set req.http.grace = "full";
      return (deliver);
    } else {

   # no graced object.
      return (fetch);
    }
  }

  # fetch & deliver once we get the result
  return (fetch); # Dead code, keep as a safeguard
}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    #
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.

 # Enable cache for all static files
  # The same argument as the static caches from above: monitor your cache size, if you get data nuked out of it, consider giving up the static file cache.
  # Before you blindly enable this, have a read here: https://ma.ttias.be/stop-caching-static-files/
  if (bereq.url ~ "^[^?]*\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpeg|jpg|js|less|mp[34]|pdf|png|rar|rtf|swf|tar|tgz|txt|wav|woff|xml|zip|webm)(\?.*)?$") {
    unset beresp.http.set-cookie;
  }


#  unset beresp.http.Cache-Control;
  if (beresp.status == 304)
  {
   set beresp.ttl = 6h;
  }


  unset beresp.http.set-cookie;
# Set 6hr cache if unset for static files
  if (beresp.ttl <= 0s || beresp.http.Set-Cookie || beresp.http.Vary == "*") {
    set beresp.ttl = 6h; # Important, you shouldn't rely on this, SET YOUR HEADERS in the backend
set beresp.uncacheable = true;
    return (deliver);
  }
set beresp.ttl = 6h;
  return (deliver);

}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    #
    # You can do accounting or modifying the final object here.


 # Called before a cached object is delivered to the client.

  if (obj.hits > 0) { # Add debug header to see if it's a HIT/MISS and the number of hits, disable when not needed
    set resp.http.X-Cache = "HIT_Cached";
  } else {
    set resp.http.X-Cache = "MISS_Cached";
  }



  # Please note that obj.hits behaviour changed in 4.0, now it counts per objecthead, not per object
  # and obj.hits may not be reset in some cases where bans are in use. See bug 1492 for details.
  # So take hits with a grain of salt
  set resp.http.X-Cache-Hits = obj.hits;

  # Remove some headers: PHP version
  unset resp.http.X-Powered-By;

  # Remove the Set-Cookie header from static assets
  if (req.http.X-static-asset) {
    unset resp.http.Set-Cookie;
  }
  # Force Safari to always check the server as it doesn't respect Vary: cookie.
  # See https://bugs.webkit.org/show_bug.cgi?id=71509
  # Static assets may be cached however as we already forcefully remove the
  # Static assets may be cached however as we already forcefully remove the
  # cookies for them.
  if (req.http.user-agent ~ "Safari" && !req.http.user-agent ~ "Chrome" && !req.http.X-static-asset) {
    set resp.http.Cache-Control = "max-age: 0";
  }

  #This will tell the client that the content served to them is fresh
  #set resp.http.Age = "0";
  
  #This will help to cach the content on browser side for 6 hrs.
  #set resp.http.Cache-Control = "max-age=21600";

  # ELB health checks respect HTTP keep-alives, but require the connection to
  # remain open for 60 seconds. Varnish's default keep-alive idle timeout is
  # 5 seconds, which also happens to be the minimum ELB health check interval.
  # The result is a race condition in which Varnish can close an ELB health
  # check connection just before a health check arrives, causing that check to
  # fail. Solve the problem by not allowing HTTP keep-alive for ELB checks.
  if (req.http.user-agent ~ "ELB-HealthChecker") {
    set resp.http.Connection = "close";
  }


  # Remove some headers: Apache version & OS
  unset resp.http.Server;
  unset resp.http.X-Drupal-Cache;
  unset resp.http.X-Varnish;
  unset resp.http.Via;
  unset resp.http.Link;
  unset resp.http.X-Generator;

  return (deliver);


}

