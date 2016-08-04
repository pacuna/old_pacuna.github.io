---
layout: post
title:  "Dockerizing a Rails API application"
comments: true
date:   2016-08-03 21:34:12
---

(This post has been excerpted from my book [Deploying Rails with Kubernetes](https://leanpub.com/deploying-rails-with-kubernetes/))

# Creating the app

Let's create a new [api-only](http://edgeguides.rubyonrails.org/api_app.html)
Rails application using [PostgreSQL](https://www.postgresql.org/)
as our database. This API will be in charge of managing articles with a small
set of fields. We just want a small microservice we can play with:

    $ rails new articles --api --database=postgresql

Now, assuming you have PostgreSQL already configured on your machine, you should
be able to create the database with:

    $ rake db:create

And to run the application with:

    $ rails s

Now if we cURL our localhost IP address from another terminal window or visit
`localhost:3000` we should see the Rails welcome page.

## Adding a resource

We said this was going to be an API for managing articles, so let's create
a simple article resource:

    $ rails g scaffold articles title:string body:text

This scaffold is actually pretty cool because it detects that our application
is api-only, so it generates a controller already adapted for
JSON responses.

Let's migrate the database:

    $ rake db:migrate

And now run the tests:

    $ rake

Output:

    Run options: --seed 3922

    # Running:

    .....

    Finished in 0.518557s, 9.6421 runs/s, 13.4990 assertions/s.

    5 runs, 7 assertions, 0 failures, 0 errors, 0 skips

If we want to test a couple of endpoints, we can always use cURL for
interacting with the API. First, we have to make sure the server is running:

    $ rails s

And then if we want to create an article we can use something like:

    $ curl -H "Content-Type: application/json" -X POST -d '{"title":"my first article","body":"Lorem ipsum dolor sit amet, consectetur adipiscing elit..."}' http://localhost:3000/articles

Output:

    {"id":1,"title":"my first article","body":"Lorem ipsum dolor sit amet, consectetur adipiscing elit...","created_at":"2016-07-23T15:40:53.352Z"

That means the article was indeed created in our database. Just in case you don't
believe me:

    $ rails c
    > Article.first
    => #<Article id: 1, title: "my first article", body: "Lorem ipsum dolor sit amet, consectetur adipiscing...", created_at: "2016-07-23 15:40:53", updated_at: "2016-07-23 15:40:53">

Cool. Now that we have our API pretty much ready, it's time to dockerize the application.

# Dockerizing

With all the Docker images available in these days, it's pretty easy to dockerize
an application. In our case we only going to need something for the Rails app
and something for PostgreSQL. In the case of Rails you have practically the same
options you have when you don't use containers for deployments. And for PostgreSQL
we can use the official image from DockerHub.

For Ruby/Rails I strongly recommend you to use the [phusion passenger-docker](https://github.com/phusion/passenger-docker) image.
It has a lot of features and a very nice documentation.

You can have a solid production application server out of the box with that image, so we will stick
with that during this book. Keep in mind that if you choose another application server
like `unicorn` or `puma`, the setup is going to be quite different.

The Docker and Docker Compose versions I'll be using for this section are:

- Docker Version 1.12
- Docker Compose version 1.8

First we are going to create a container environment by using Docker Compose.

The application needs to be build using the phusion passenger-docker as the base image. So
we need a Dockerfile. This Dockerfile is also going to add some extra files.

The typical configuration that you need for this image, are the virtual host
for your application and a file for declaring the environmental variables
you may need in your application. First, let's create a file for holding
the virtual host configuration:

    $ touch webapp.conf

And add the following to that file:

    server {
        listen 80;
        server_name www.webapp.com;
        root /home/app/webapp/public;

        passenger_enabled on;
        passenger_user app;

        passenger_ruby /usr/bin/ruby2.3;
    }

As you can see we have a very simple virtual host configuration for Nginx and passenger. This
file will be added to the available hosts of the server during the container
build.

Now let's add a file for the environmental variables. We'll put some just
so we know how to declare them later:

    $ touch rails-env.conf

And add the following:

    env SECRET_KEY_BASE;
    env DATABASE_URL;
    env DATABASE_PASSWORD;

We won't be using those variables during development so don't worry about them
for now. You just need to know that every environmental variable that you need
in your application should be declared here so they are preserved and forwarded to your
web application.

Now we can create the Dockerfile that's going to add those files along the entire application.
I've added comments for every instruction so you can know what's happening
on every step during the build. If you still have doubts about some instructions,
just go to the [official repository](https://github.com/phusion/passenger-docker)
of the image and take a look at the documentation, it's really good.

    $ touch Dockerfile

And the content:

    FROM phusion/passenger-ruby23:0.9.19

    # Set correct environment variables.
    ENV HOME /root

    # Use baseimage-docker's init process.
    CMD ["/sbin/my_init"]

    # Additional packages: we are adding the netcat package so we can
    # make pings to the database service
    RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-confold" netcat

    # Enable Nginx and Passenger
    RUN rm -f /etc/service/nginx/down

    # Add virtual host entry for the application. Make sure
    # the file is in the correct path
    RUN rm /etc/nginx/sites-enabled/default
    ADD webapp.conf /etc/nginx/sites-enabled/webapp.conf

    # In case we need some environmental variables in Nginx. Make sure
    # the file is in the correct path
    ADD rails-env.conf /etc/nginx/main.d/rails-env.conf

    # Install gems: it's better to build an independent layer for the gems
    # so they are cached during builds unless Gemfile changes
    WORKDIR /tmp
    ADD Gemfile /tmp/
    ADD Gemfile.lock /tmp/
    RUN bundle install

    # Copy application into the container and use right permissions: passenger
    # uses the app user for running the application
    RUN mkdir /home/app/webapp
    COPY . /home/app/webapp
    RUN usermod -u 1000 app
    RUN chown -R app:app /home/app/webapp
    WORKDIR /home/app/webapp


    # Clean up APT when done.
    RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

    EXPOSE 80

That Dockerfile should do the trick for our Rails application. It might seem a little
bit complicated at first, but trust me, you'll get used to it after building a
couple of Rails services.

The cool thing about this setup, is that you'll be using
the same server for development and production, so you'll have a lot less work to do
when you ship to production. This image in particular uses the `PASSENGER_APP_ENV`
variable for setting the environment. So for example in Rails, that variable
controls the `RAILS_ENV` variable.

Now that we have the Dockerfile for building our application, we need a Docker
Compose file so we can run the database and then test these containers to see
if everything works fine.

We'll need three services in our Docker Compose file. One for our web application,
one for the PostgreSQL database, and one for running initialization commands.
This setup container will be run only once before the actual application, and it's
going to migrate our database.

## Setup Container

Like I mentioned before, we need a mechanism for running some initialization commands.
In a Rails application, these are typically `rake db:create`, `rake db:migrate`
and `rake assets:precompile`. We can't run those commands in the same container
that we're running our web application. That would work fine if you're deploying
only one container, but suppose you want to scale your application and you want to run
ten containers, then every one of those containers will be trying to execute
those commands during startup time and things can get ugly. With that said, it's
always better to separate concerns and to use an independent container for running
tasks and then just remove it once it finishes.

This setup container has to use the same Dockerfile that we just created
since it needs access to the whole application. The only part we need to
overwrite the entrypoint.

Right now we don't have an entrypoint for
our web application container since we want to use the one that the same image
is providing for us. But since this setup container doesn't need to be running as a web application, we
can just overwrite it with our own initialization commands. Let's create this new entrypoint script
in our root path:

    $ touch setup.sh

And add the following:

    #!/bin/sh

    echo "Waiting PostgreSQL to start on 5432..."

    while ! nc -z postgres 5432; do
      sleep 0.1
    done

    echo "PostgreSQL started"

    rake db:migrate

The whole purpose of this script is to run the possible new
migrations our application may have. But, what if the database is not yet
available for the rake task? That would generate an error and the whole
run would crash. That's why we use a while expressions that's going to loop
until the connection is alive. We are using the `netcat` package for this and assuming
that the PostgreSQL service endpoint will be reachable by using the `postgres`
alias. Finally, when the connection is alive, we can run the latests migrations.
This type of scripts are very usual when you need to orchestrate different services
that are constantly being shut down and turned on.

Let's create the `docker-compose.yml` file in our root path and add the service:

    $ touch docker-compose.yml

And the service:

    version: '2'
    services:
      webapp_setup:
        build: .
        depends_on:
          - postgres
        environment:
          - PASSENGER_APP_ENV=development
        entrypoint: ./setup.sh

This service will use the Dockerfile we already have for the build. It has
a dependency on a service we haven't declared yet and which name will be `postgres`.

We are also passing an environmental variable for the Rails environment. This is one
of the ways of setting the `RAILS_ENV` variable for this image and it's described
in the documentation.

Finally, we are overwriting the entrypoint with the previous bash script.
Since this script doesn't do anything after the migration, the container will be exited
when it finishes, which is want we want.

## Web Application Container

This service will be similar to the setup service. The differences are:

- We need to declare a dependency on the setup container so it always runs after it
- We need to map the port 80 of the container to our host if we want to access our application via HTTP

We can express all of that with:

    webapp:
      build: .
      depends_on:
        - postgres
        - webapp_setup
      environment:
        - PASSENGER_APP_ENV=development
      ports:
        - "80:80"

As you can see in this service, we are not touching the entrypoint. The default one
provided by the base image will be executed and the application will be launched as a web
application.

## Database Container

The PostgreSQL service will be very simple. We need to pull the `postgres:9.5.3` image
from the DockerHub and set up a couple of environmental variables like the user,
password and database name:

    postgres:
      image: postgres:9.5.3
      environment:
        - POSTGRES_PASSWORD=mysecretpassword
        - POSTGRES_USER=articles

If we don't declare the database name, the container will create one with the same
user name. In this case our user and database will be `articles`.
Since the container will create this database during startup, we don't need to run `rake db:create`
in our application initialization script.

You can get fancy and add data volumes for persisting the database data and for
mounting your source into the web application container, but since this book
is more about deployment, and also because later will see how to persist data
on production by using AWS volumes, let's just leave it like that.

Keep in mind that for a daily development workflow, you **want** to mount your source
file into the application container. That way you can see your changes immediately
inside of the container. You can accomplish this with just one line of code:

    volumes:
      - .:/path-to-my-source

That's going to mount your local source code to the folder where the application
lives inside of the container.

The final `docker-compose.yml` file should look like this:

    version: '2'
    services:
      webapp_setup:
        build: .
        depends_on:
          - postgres
        environment:
          - PASSENGER_APP_ENV=development
        entrypoint: ./setup.sh
      webapp:
        build: .
        depends_on:
          - postgres
          - webapp_setup
        environment:
          - PASSENGER_APP_ENV=development
        ports:
          - "80:80"
      postgres:
        image: postgres:9.5.3
        environment:
          - POSTGRES_PASSWORD=mysecretpassword
          - POSTGRES_USER=articles

### Build and Run

Let's run a Docker Compose build first for building our web application and
setup containers:

    $ docker-compose build

Output:

    postgres uses an image, skipping
    Building webapp_setup
    Step 1 : FROM phusion/passenger-ruby23:0.9.19
    f069f1d21059: Pull complete
    ecbeec5633cf: Pull complete
    ea6f18256d63: Pull complete
    54bde7b02897: Pull complete
    a3ed95caeb02: Pull complete
    ce9e695a6234: Pull complete
    346026b9659b: Extracting [=============================================>     ] 29.16 MB/32.19 MB
    ffaf5356e027: Download complete
    85417a8aee4f: Downloading [===============>                                   ] 45.33 MB/147.5 MB
    ...
    (truncated)

The first time you run this command it may take some time, since the Docker engine has
to pull the image, install the dependencies and install the gems. At the end
you should see something like this in the output:

    (truncated)
    Step 16 : RUN chown -R app:app /home/app/webapp
     ---> Using cache
     ---> 54deb341aead
    Step 17 : WORKDIR /home/app/webapp
     ---> Using cache
     ---> 1ed66ec118c5
    Step 18 : RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
     ---> Using cache
     ---> ac2951626316
    Step 19 : EXPOSE 80
     ---> Using cache
     ---> 47e8a4833c88
    Successfully built 47e8a4833c88

Meaning that the web application image was successfully built.
Now we can run the Docker Compose up command to pull the PostgreSQL image,
run the initialization script and setup the entire system:

    $ docker-compose up

Some interesting parts you can see in the output are:


    Pulling postgres (postgres:9.5.3)...
    5c90d4a2d1a8: Extracting [=================================================> ] 50.86 MB/51.35 MB
    5c90d4a2d1a8: Downloading [===========================>                       ] 28.25 MB/51.35 MBd complete
    c3961b297acc: Download complete
    ...

For the PostgreSQL image pull,

    postgres_1      | server started
    postgres_1      | CREATE DATABASE
    postgres_1      |
    postgres_1      | CREATE ROLE
    postgres_1      |
    postgres_1      |
    postgres_1      | /docker-entrypoint.sh: ignoring /docker-entrypoint-initdb.d/*
    postgres_1      |
    postgres_1      | LOG:  received fast shutdown request
    postgres_1      | LOG:  aborting any active transactions
    postgres_1      | waiting for server to shut down....LOG:  autovacuum launcher shutting down
    postgres_1      | LOG:  shutting down
    postgres_1      | LOG:  database system is shut down
    webapp_setup_1  | Waiting PostgreSQL to start on 5432...
    postgres_1      |  done
    postgres_1      | server stopped
    postgres_1      |
    postgres_1      | PostgreSQL init process complete; ready for start up.
    postgres_1      |
    postgres_1      | LOG:  database system was shut down at 2016-07-23 21:59:34 UTC
    postgres_1      | LOG:  MultiXact member wraparound protections are now enabled
    postgres_1      | LOG:  database system is ready to accept connections
    postgres_1      | LOG:  autovacuum launcher started
    webapp_setup_1  | PostgreSQL started
    postgres_1      | LOG:  incomplete startup packet
    webapp_setup_1  | == 20160723153218 CreateArticles: migrating ===================================
    webapp_setup_1  | -- create_table(:articles)
    webapp_setup_1  |    -> 0.0095s
    webapp_setup_1  | == 20160723153218 CreateArticles: migrated (0.0096s) ==========================
    webapp_setup_1  |
    articles_webapp_setup_1 exited with code 0

And here in my case you can see our script in action. If you look at the line that says:

    webapp_setup_1  | Waiting PostgreSQL to start on 5432...

You can see the setup container trying to connect to the PostgreSQL container
in order to run the migrations, but the PostgreSQL initialization wasn't ready yet.

Then you see our `PostgreSQL started` message almost at the end and then the database migration being executed.
You can also see the setup container being exited.

Finally you'll see something like this:

    webapp_1        | [ 2016-07-23 21:59:34.0235 29/7fcb59860780 age/Wat/WatchdogMain.cpp:1291 ]: Starting Passenger watchdog...
    webapp_1        | [ 2016-07-23 21:59:34.0414 32/7f7300922780 age/Cor/CoreMain.cpp:982 ]: Starting Passenger core...
    webapp_1        | [ 2016-07-23 21:59:34.0415 32/7f7300922780 age/Cor/CoreMain.cpp:235 ]: Passenger core running in multi-application mode.
    webapp_1        | [ 2016-07-23 21:59:34.0433 32/7f7300922780 age/Cor/CoreMain.cpp:732 ]: Passenger core online, PID 32
    webapp_1        | [ 2016-07-23 21:59:34.0666 41/7f3ed7fe5780 age/Ust/UstRouterMain.cpp:529 ]: Starting Passenger UstRouter...
    webapp_1        | [ 2016-07-23 21:59:34.0676 41/7f3ed7fe5780 age/Ust/UstRouterMain.cpp:342 ]: Passenger UstRouter online, PID 41

Which indicates that the passenger and Nginx processes are ready and listening.

Let's test the application via cURL. You should replace the localhost address
with whatever you're using for running Docker. In my case I'm using Docker for Mac,
so my Docker IP is localhost. Also remember not to kill the Docker Compose up process.

Open a different tab and test the create endpoint:

    $ curl -H "Content-Type: application/json" -X POST -d '{"title":"my first article","body":"Lorem ipsum dolor sit amet, consectetur adipiscing elit..."}' http://localhost/articles

Output:

    {"id":1,"title":"my first article","body":"Lorem ipsum dolor sit amet, consectetur adipiscing elit...","created_at":"2016-07-23T22:06:59.882Z","update...

Awesome! That means our application is up and running. I can go and visit `http://localhost/articles`
and see the article we just created.
