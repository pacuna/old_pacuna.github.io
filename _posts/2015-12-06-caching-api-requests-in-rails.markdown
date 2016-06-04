---
layout: post
title:  "Caching API requests in Rails"
comments: true
date:   2015-12-06
---

I'm currently working on a project that makes a lot of calls to external APIs
such as Google Analytics, Mailchimp, Google's double click for publishers, etc.
And a couple of internal API calls.  All of this for generating reports for our commercial team. 

Generating these reports can take up to 2-3 minutes, so it would be nice to have some kind of cache mechanism.
This way if somebody wants to revisit the report later, it's not going to take 
that amount of time for the report being displayed.

The library that I'm using for making the requests it's called [Typhoeus](https://github.com/typhoeus/typhoeus).
It's pretty cool because it wraps all of the dirty and difficult to remember
methods from the lower level HTTP libraries in a very clean DSL. And a very pleasant thing that I
discovered is that it includes build in support for caching.

Suppose we have this method that calls some external API:

{% highlight ruby %}
def my_method
  JSON.parse(Typhoeus.get("http://some.external.api").body)
end
{% endhighlight %}

Every time you call this method, you're going to be hitting that endpoint.
Now, with Typhoeus you can declare a cache class and pass that class to the cache configuration
using an initializer:


{% highlight ruby %}
class Cache
  def get(request)
    Rails.cache.read(request)
  end

  def set(request, response)
    Rails.cache.write(request, response)
  end
end

Typhoeus::Config.cache = Cache.new
{% endhighlight %}

Remember that if you want to test this in development mode, you must 
have this line in your config/environments/development.rb:

{% highlight ruby %}
config.action_controller.perform_caching = true
{% endhighlight %}

And that's it. Now the first time you call some endpoint using Typhoeus, 
the result will be cached and will be served by the cache system that you're using
in your Rails application.

One thing that's not very clear in the Typhoeus documentation, is how to pass
options to the Cache class methods. In my case I needed an expiration time.
After some research I found out that is as simple as passing the options as a third argument
to the method, so in my case it would be:

{% highlight ruby %}
def set(request, response)
  Rails.cache.write(request, response, expires_in: 3.hours)
end
{% endhighlight %}

Lastly, remember that all of the responses will be cached, even the bad ones.
So if your endpoint responds with an error, you'll have to clear the cache. Remember that
is not a good practice to parse requests using the JSON library without checking if
the response is correct first. Or else you'll ended up having very ugly errors.

Thanks for reading!
