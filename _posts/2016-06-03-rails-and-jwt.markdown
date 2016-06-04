---
layout: post
title:  "Authorizing Rails (micro)services with JWT "
comments: true
date:   2016-06-03 23:36:12
---

## Introduction

So, let's say that like me, you don't want to implement OAuth for communicating
your Rails API calls, but you're still looking for something safer that just
create your own new sloppy token schema.
Well, a pretty good alternative are [JWT](https://jwt.io/) (JSON Web Tokens).
I'm not going to explain the concept in a very technical way because I'm all
about implementation, but basically it works like this:

  - In the secured API you have a database with user credentials (e.g. username and password)
  - The application that makes requests generates a POST request to some login endpoint in the API (e.g. POST /user_token)
  - The API generates a token using a secure algorithm that contains all the necessary information about the user that's making the request
  - The application uses this token for all the following requests by sending it in their headers
  - The API decodes the token and authorizes the user to receive the responses.

That's JWT at their basics. Of course there's a lot more technicalities behind them
and there are a lot of good resources out there to learn.

## Implementation

We're going to use the [knock gem](https://github.com/nsarno/knock). This gem
wraps a big part of the complexity and it integrates itself very nicely with the native
Rails authentication.

First, let's generate an API. I'm using ruby 2.3.1 and Rails 5.0.0.rc1:

```
  $ rails new my_api --api
```

Now let's create our users table with secure password:

```
  $ rails g model user email:string password_digest:string
  $ rake db:migrate
```

Install the knock gem (following the repo instructions):

```
gem 'knock'
```

```
$ bundle install
$ rails generate knock:install
$ rails generate knock:token_controller user
```

Those commands will generate an initializer with some customization options and
the route and controller for retrieving the token.

Now let's add the secure password method to our model so knock can have an
authentication method:

```
class User < ApplicationRecord
  has_secure_password
end
```

Now open a rails console and create a user:

```
 $  rails c
  > User.create(email: 'admin@mail.com', password: 'securepassword', password_confirmation: 'securepassword')
```

Cool, we are almost there. Open your Application Controller and add the Knock
Module to it:

```
class ApplicationController < ActionController::API
  include Knock::Authenticable
end
```

And that's it for the setup. Now we can start creating resources and
adding a filter. Let's add new resource so we can test it:

```
$ rails g resource articles title:string body:text
$ rake db:migrate
```

And create some entries:

```
  $ rails c
  > Article.create(title: 'first article', body: 'first article body')
  > Article.create(title: 'second article', body: 'second article body')
```

Now, open the controller and add this filter and action:

```
class ArticlesController < ApplicationController
  before_action :authenticate_user

  def index
    render json: Article.all
  end
end
```

That index action is secured. First let's try to hit that endpoint
without authentication via cURL:

```
$ rails s --port 3000
```

```
$ curl -I localhost:3000/articles

HTTP/1.1 401 Unauthorized
X-Frame-Options: SAMEORIGIN
X-XSS-Protection: 1; mode=block
X-Content-Type-Options: nosniff
Content-Type: text/html
Cache-Control: no-cache
X-Request-Id: fec8f4c4-b8f4-40f6-9971-7b6f0438f8cd
X-Runtime: 0.141929
```

Nice! We have a 401 response from the server. That means the filter is working.
Now let's hit the route that can gives us a token by passing the credentials:

```
$ curl -H "Content-Type: application/json" -X POST -d '{"auth":{"email":"admin@mail.com","password":"securepassword"}}' http://localhost:3000/user_token

{"jwt":"eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE0NjUwOTYxMzMsInN1YiI6MX0.e9yeOf_Ik8UBE2dKlNpMu2s6AzxvzcGxw2mVj9vUjYI"}%
```

If we get the JWT token, it means that the login was successful. Now we can make
requests by sending that token in the header in the following way:

```
$ curl -i http://localhost:3000/articles -H "Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE0NjUwOTYxMzMsInN1YiI6MX0.e9yeOf_Ik8UBE2dKlNpMu2s6AzxvzcGxw2mVj9vUjYI"


HTTP/1.1 200 OK
X-Frame-Options: SAMEORIGIN
X-XSS-Protection: 1; mode=block
X-Content-Type-Options: nosniff
Content-Type: application/json; charset=utf-8
ETag: W/"56960b8def640a1b6091df1cd3b0976e"
Cache-Control: max-age=0, private, must-revalidate
X-Request-Id: d5ee7045-546d-478e-9748-a11d99a6a00f
X-Runtime: 0.014365
Transfer-Encoding: chunked

[{"id":1,"title":"first article","body":"first article body","created_at":"2016-06-04T03:04:25.997Z","updated_at":"2016-06-04T03:04:25.997Z"},{"id":2,"title":"second article","body":"second article body","created_at":"2016-06-04T03:04:39.995Z","updated_at":"2016-06-04T03:04:39.995Z"}]%
```

We got our articles back, so it's working. Now let's see how to
consume this endpoint from another Rails service. Let's
create a new application:

```
  $ rails new consumer --api
```

Let's add a route:

```
Rails.application.routes.draw do
  get '/articles', to: 'articles#index'
end
```

And a controller with an action that's going to make a call to the articles endpoint:

```
class ArticlesController < ApplicationController
  def index

  end
end
```

Now, first we have to make a post request in order to get the token back:

```
    uri = URI.parse('http://localhost:3000/user_token')
    req = Net::HTTP::Post.new(uri, initheader = {'Content-Type' =>'application/json'})
    req.body = { auth: {email: 'admin@mail.com', password: 'securepassword'}}.to_json
    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    jwt_token = JSON.parse(res.body)['jwt']
```

That's a pretty simple use of the Net::HTTP ruby library, basically the same
thing we did with cURL.

Now that we have that token, we can send it along the request:

```
    uri = URI.parse("http://localhost:3000/articles")
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Get.new uri
      request.add_field("Authorization", "Bearer #{jwt_token}")
      response = http.request request
      render json: JSON.parse(response.body)
    end
```

You see that's a regular http get request, but with a header that contains
the Authorization field.

Let's run this application and see if we can get the response:

```
$ rails s --port 4000
```

```
$ curl http://localhost:4000/articles

[{"id":1,"title":"first article","body":"first article body","created_at":"2016-06-04T03:04:25.997Z","updated_at":"2016-06-04T03:04:25.997Z"},{"id":2,"title":"second article","body":"second article body","created_at":"2016-06-04T03:04:39.995Z","updated_at":"2016-06-04T03:04:39.995Z"}]%
```

Great! If you hit that URL in you're browser you should also see the JSON response.
If you don't see the response, make sure you're passing the correct credentials when getting the token

Your final controller should look like this:

```
class ArticlesController < ApplicationController
  def index
    uri = URI.parse('http://localhost:3000/user_token')
    req = Net::HTTP::Post.new(uri, initheader = {'Content-Type' =>'application/json'})
    req.body = { auth: {email: 'admin@mail.com', password: 'securepassword'}}.to_json
    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    jwt_token = JSON.parse(res.body)['jwt']

    uri = URI.parse("http://localhost:3000/articles")
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Get.new uri
      request.add_field("Authorization", "Bearer #{jwt_token}")
      response = http.request request
      render json: JSON.parse(response.body)
    end

  end
end
```

In case you wonder, YES! You should refactor this code into a service
or whatever thing you use for reusing code and avoiding big methods.

And that's it! A very light and easy to implement mechanism for communicating
your Rails API services (or microservices).

Thanks for reading.
