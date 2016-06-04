---
layout: post
title:  "Automatic Log into ECS Container Instances"
comments: true
date:   2015-12-07
---

The title of this this post is kind of ambiguous. I didn't know how else to put
it. I'll describe it better telling you about the problem we had.

We have an ECS cluster with several container instances running different
services. If you have played before with Amazon ECS you'll know that's pretty
difficult to ssh inside of your applications in a fast way. A lot of people say that is a bad 
practice to do this, but at the end, when you're running
applications in production environments, eventually you are going to need to access the
application. Maybe for inspecting a log, for running a task or a command, etc.

Amazon ECS uses the concept of services and tasks for running applications.
The container is going to be launch via a task which is going to be managed and
scheduled by a service. 
Since ECS wraps the docker container with the elements of its own architecture, 
it can be difficult to find your tasks and log into your container.
The good thing is you have access to the AWS API (which is a fantastic API IMO)
and using a short script it's possible to find the instance that's running some
task by passing the service name.

In this case I'm using the ruby version of the API:

{% highlight ruby %}
#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'aws-sdk'

# pass the service name as the only argument
service_name = ARGV[0]

Aws.config.update({
  region: 'YOURREGION',
  credentials: Aws::Credentials.new('YOURKEY', 'YOURSECRET'),
})


# we'll need to use both the ecs and ec2 apis
ecs = Aws::ECS::Client.new(region: 'YOURREGION')
ec2 = Aws::EC2::Client.new(region: 'YOURREGION')

# first we get the ARN of the task managed by the service
task_arn = ecs.list_tasks({cluster: 'MYCLUSTER', desired_status: 'RUNNING', service_name: service_name}).task_arns[0]

# using the ARN of the task, we can get the ARN of the container instance where its being deployed
container_instance_arn = ecs.describe_tasks({cluster: 'MYCLUSTER', tasks: [task_arn]}).tasks[0].container_instance_arn

# with the instance ARN let's grab the intance id
ec2_instance_id = ecs.describe_container_instances({cluster: 'MYCLUSTER', container_instances: [container_instance_arn]}).container_instances[0].ec2_instance_id

# we need to describe the instance with this id using the ec2 api
instance = ec2.describe_instances({instance_ids: [ec2_instance_id]}).reservations[0].instances[0]

# finally we can get the name of the instance we need to log in
name = instance.tags.select{|n| n['key'] == 'Name'}[0].value

# ssh into the machine
exec "ssh #{name}"

{% endhighlight %}

Now you can run `./myscript service-name` and you'll be automatically logged into
the container instance that's running your task. Then you can run `docker ps` to
get the container id and finally `docker exec -it CONTAINER_ID bash` to log into
the container. Much faster than going to the ECS web console or running
`docker ps` in all your cluster instances until you find the one that has the task you're looking for.

I'm not sure if there's a better way of doing this but it works for my use case.
For the automatic login, you'll need to have an alias for each instance in your ssh config file:

```
Host name-1
HostName XX.XX.XX.XX
User ec2-user
IdentityFile /path/to/my/pem/file

Host name-1
HostName XX.XX.XX.XX
User ec2-user
IdentityFile /path/to/my/pem/file
```

This way if the script find the host named `name-1`,
it can run `ssh name-1` and then you can log into your container.

If you're interested in learn more about Rails and Amazon ECS, I'm writing
[a book](https://leanpub.com/rails-on-docker) that covers all the essential parts in the deployment process.

That's it, thanks for reading!

