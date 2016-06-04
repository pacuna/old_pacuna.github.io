---
layout: post
title:  "Rails development with Docker and Vagrant"
comments: true
date:   2015-05-31
---

I'm developing Rails applications most of my time, so I've been trying to 
create a flexible and comfortable development environment that can be easily 
reproduced in production. This means that I want to start to develop right away 
using a real production app server and a real database, so no webrick or sqlite 
in this post, just real useful stuff.

## Environment

I'm going to show you how to setup a Rails environment using Nginx and 
Passenger for serving your application, and MySQL for your data. I know a lot 
of people prefer postgresql but the setup is pretty similar (I'm using MySQL 
for work related reasons).

We will use [Docker](https://www.docker.com/) inside 
[Vagrant](https://www.vagrantup.com/). I think this approach is more flexible 
and universal that using just Docker since that can generate 
inconsistencies between workspaces using boot2docker in OS X (like me) and
workspaces using Linux distributions as host machine. Besides, Vagrant gives us 
native docker provisioning which can reduce a lot of Docker typing.

Note: I know about tools like Docker compose but since it's still not suitable
for production, I prefer to use just native Docker commands for linking
and running my containers.

## Steps

### Create a Rails applicacion

We're going to start with a fresh Rails application. So in your local machine 
create a new applicacion and select MySQL as the database.

```
rails new myapp -d mysql
```

### Dockerfile for the application

We can use 
[the official Passenger image](https://github.com/phusion/passenger-docker) 
for getting a crafted environment configured by the official phusion team.
Following the instructions from the repository, you get a very minimal
Dockerfile.

{% highlight docker %}
FROM phusion/passenger-ruby22:0.9.15

# Set correct environment variables.
ENV HOME /root

# Use baseimage-docker's init process.
CMD ["/sbin/my_init"]


# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Active nginx
RUN rm -f /etc/service/nginx/down

# Copy the nginx template for configuration and preserve environment variables
RUN rm /etc/nginx/sites-enabled/default
ADD myapp.conf /etc/nginx/sites-enabled/myapp.conf
ADD mysql-env.conf /etc/nginx/main.d/mysql-env.conf

# Create the folder for the project and set the workdir
RUN mkdir /home/app/myapp
WORKDIR /home/app/myapp

# Copy the project inside the container and run bundle install
COPY Gemfile /home/app/myapp/
COPY Gemfile.lock /home/app/myapp/
RUN bundle install
COPY . /home/app/myapp

# Set permissions for the passenger user for this app
RUN chown -R app:app /home/app/myapp

# Expose the port
EXPOSE 80
{% endhighlight %}

The myapp.conf is just a basic nginx configuration for serving the application:

{% highlight nginx %}
server {
    listen 80;
    server_name www.webapp.com;
    root /home/app/myapp/public;

    passenger_enabled on;
    passenger_user app;

    passenger_ruby /usr/bin/ruby2.2;
}
{% endhighlight %}

And the mysql-env.conf file is necessary for preserving the environment variables
passed from Docker to passenger. You can find more info about this in the
image repository. In this case we just need the variables comming from the
MySQL container that we will be linking with our app.
If you need to pass more enviroment variables, just put them in this file

```
env MYSQL_ENV_MYSQL_ROOT_PASSWORD;
env MYSQL_PORT_3306_TCP_ADDR;
```

Put this files in the root of your application (Dockerfile, myapp.conf
and mysql-env.conf).

## Vagrant stuff

For Vagrant, create a new folder in your application and initialize
it with a fresh Vagrantfile

```
mkdir vagrant
cd vagrant
vagrant init
```

Replace the generated Vagrantfile with the following configuration:

{% highlight ruby %}
# -*- mode: ruby -*-

Vagrant.configure(2) do |config|
  config.vm.box     = "trusty"

  config.vm.box_url = "https://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box"
  
  config.vm.network "forwarded_port", guest: 80, host: 8080

  config.vm.network "private_network", ip: "33.33.33.54"

  config.vm.synced_folder "../", "/myapp", :mount_options => ["uid=9999,gid=9999"]

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
  end
  
  config.vm.provision "docker" do |d|
    d.pull_images "mysql:5.7"

    d.build_image "/myapp", args: "-t myapp"

    d.run "mysql:5.7",
      auto_assign_name: false,
      daemonize: true,
      args: "--name myapp-db -e MYSQL_ROOT_PASSWORD=myapp"

    d.run "myapp",
      auto_assign_name: false,
      daemonize: true,
      args: "--name myapp -p 80:80 --link myapp-db:mysql -e PASSENGER_APP_ENV=development -v '/myapp:/home/app/myapp'"
  end

end
{% endhighlight %}

lets analyze this file.

{% highlight ruby %}
config.vm.box = "trusty"

config.vm.box_url = "https://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box"

config.vm.network "forwarded_port", guest: 80, host: 8080

config.vm.network "private_network", ip: "33.33.33.54"
{% endhighlight %}

This is just regular Vagrant stuff, we're fetching the trusty image for Ubuntu, 
forwarding ports to our host machine and setting a private network in order to 
access our running applicacion using our host machine browser.

{% highlight ruby %}
  config.vm.synced_folder "../", "/myapp", :mount_options => ["uid=9999,gid=9999"]
{% endhighlight %}

This line is important. We're sharing our application folder, but in order to 
not messed up the permissions for the passenger user (with uid 9999) we have to
set permissions for the mounted folder.

{% highlight ruby %}
  config.vm.provision "docker" do |d|
    d.pull_images "mysql:5.7"

    d.build_image "/myapp", args: "-t myapp"

    d.run "mysql:5.7",
      auto_assign_name: false,
      daemonize: true,
      args: "--name myapp-db -e MYSQL_ROOT_PASSWORD=myapp"

    d.run "myapp",
      auto_assign_name: false,
      daemonize: true,
      args: "--name myapp -p 80:80 --link myapp-db:mysql -e PASSENGER_APP_ENV=development -v '/myapp:/home/app/myapp'"
  end
{% endhighlight %}

This section is where the magic happens. Using the Docker provisioning
we can automate several stuff (I'm using Vagrant 1.7.2 in case you wonder).

Firt, we tell vagrant that we want to pull the MySQL image from the Docker
registry in order to be available right away after a provisioning. Next,
we're telling Vagrant that we have a local image in our shared folder and we want
to build it and call it "myapp". This way Vagrant is going to look for a Dockerfile
in that folder and execute a Docker build using the provided args. Pretty neat.

The following two segments are necessary for running the previously pulled and 
built images.
The [MySQL image](https://github.com/docker-library/docs/tree/master/mysql)
is being runned in a very standard way.

For our "myapp" application we need to expose the port 80 from the container
to the host, create a Docker link with the mysql container, set the passenger 
environment variable, and mounting a volume for working locally and not have 
to rebuild the image every time we make changes in the code.

The last thing we need to do is change the MySQL configuration in our
config/databases.yml file.

{% highlight yaml %}
default: &default
  adapter: mysql2
  encoding: utf8
  pool: 5
  username: root
  password: <%= ENV['MYSQL_ENV_MYSQL_ROOT_PASSWORD'] %>
  host: <%= ENV['MYSQL_PORT_3306_TCP_ADDR'] %>

development:
  <<: *default
  database: myapp_development

test:
  <<: *default
  database: myapp_test

production:
  <<: *default
  database: myapp_production
{% endhighlight %}

Here we're using the environment variables that the MySQL container shared 
with the Rails application container.

## Running all the stuff

Now that's all in place, we can run

```
cd vagrant
vagrant up
```

and wait until the command is finished.

## Verification

In order to verify that nothing went wrong, we can go to the VM IP (33.33.33.54) and check
if the Rails application is running.

The first time you should see this error:

![error]({{ site.url }}/assets/2015-05-31-rails-docker/error.png)


Easy to fix, we just have to execute a rake db:create command inside
the passenger container. Remember that we named it 'myapp':

```
vagrant ssh
cd /myapp
docker exec -it myapp rake db:create
```

Now if you visit the ip you should see the classical Rails welcome. Great!
![welcome]({{ site.url }}/assets/2015-05-31-rails-docker/welcome.png)

## Workflow

I'm not sure if there's a convention about how to work with Rails and 
containers yet. But in my case I haven't had problems using the shared
folders and running the Rails and rake commands against the container.

For example, if you want to scaffold something, you can do something like this:

```
vagrant ssh
cd /myapp
docker exec -it myapp rails g scaffold posts title body:text
docker exec -it myapp rake db:migrate
```

Then if you visit the VM ip in the /posts route, you'll see your scaffold running
as usual. The data is connected to the MySQL database container

![scaffold]({{ site.url }}/assets/2015-05-31-rails-docker/scaffold.png)

One important detail is that Vagrant is going
to run your container only during provisioning. If you run a vagrant halt
and then just vagrant up, your images are still going to be there, but
they are not going to be running.

In my case it's fine run vagrant up --provision every time, since pulling
the images is going to be super fast thanks to the Docker cache.

The beauty of all this setup, is that if you want to deploy your application
in production, you just need a machine with Docker installed and run
your containers, and you can be pretty sure that is going to work in the same way
as in your development environment.

In future posts I'll talk more about what I've learn about deploying and manage
your containers in different nodes of a cluster in production.

Thanks for reading!.
