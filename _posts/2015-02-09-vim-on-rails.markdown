---
layout: post
title:  "Vim On Rails"
comments: true
date:   2015-02-09 21:05:12
---

I'm going to talk about some of the plugins and configuration that
I use every day at work, which is mostly developing Ruby on Rails applications.

In my case there are some elements that make a big difference when
using a text editor:

- Switching between files and directories
- VCS support (git of course)
- Movement inside of a file
- Shortcuts that make my life easy

Of course some of these elements can be irrelevant for other users. But I think that any Rails
developer could gain a lot using an editor with good support for all of these features.

So, let's go to the good stuff.

## Switching between files and directories

There's this great plugin written by Tim Pope called [vim-rails](https://github.com/tpope/vim-rails)
that adds a lot of sweet commands to Vim.

You can use *:Econtroller* to navigate controllers, 
*:Emodel* to go to some model, *:Eview* for views, *:Emailer* to...well, you get the idea.

The best thing about this commands is you can use *tab* for autocompletion.
You can also use reduced versions for some of them. For example *:Econtroller* comes
aliased as *:Eco* and *:Emodel* as *:Emo*.

![Ecommands]({{ site.url }}/assets/2015-02-09-vim-on-rails/Ecommands.gif)

Other cool Ecommands that I use a lot, are *:Emigration* and *:Einitializer*.
*:Emigration* takes you to the latest migration. Super useful if you use the Rails
migration generator and want to verify if everything it's OK with the last generated migration. 
*:Einitializer* takes you to the routes.rb file. All experienced Rails developer knows
that he's going to make a lot of visits to that file.


![EinitializerEmigration]({{ site.url }}/assets/2015-02-09-vim-on-rails/EinitializerEmigration.gif)

If you are into testing (and I hope you are), you need to start using the *:Alternate*
command. It takes you to the related file of the current file. Personally
I just use it to go from Model/Controller to the corresponding test file. The short version
is *:A*. So if you are in the User model and execute the *:A* command, it takes
you to the User spec.
This command is highly customizable, but as I mentioned before, I've been using it just to
navigate to the specs and viceversa.

![Alternate]({{ site.url }}/assets/2015-02-09-vim-on-rails/alternate.gif)

### Explorer type navigation

If you're used to file navigation using a tree-type explorer, try
[vim-vinegar](https://github.com/tpope/vim-vinegar).
In [this](http://vimcasts.org/blog/2013/01/oil-and-vinegar-split-windows-and-project-drawer/) post
there's a great explanation about why vim-vinegar is superior to NerdTree.
Basically you can turn any buffer into a file explorer. This way you never get confused
about which buffer is going to be replaced when selecting some file in the explorer and you have split windows.

Vim-vinegar can be used to do all standard operations like
creating, deleting and moving files. I've been using this plugin a lot and
I can tell you that has made a huge difference in my workflow.

![Vinegar]({{ site.url }}/assets/2015-02-09-vim-on-rails/vinegar.gif)

### Comments and *ends*

Two small plugins that are going to save you some time are [vim-commentary](https://github.com/tpope/vim-commentary)
and [vim-endwise](https://github.com/tpope/vim-endwise).
The first one is a solid implementation of a line commenting plugin
and the second adds *end* statements after declaring some method definition or a block.

![Comment-endwise]({{ site.url }}/assets/2015-02-09-vim-on-rails/comment-endwise.gif)

### VCS support

This section only covers Git Version Control, because come on.

Vim has probably the best Git wrapper of all text editors out there.
[vim-fugitive](https://github.com/tpope/vim-fugitive) if one of those
things that with the time becomes an indispensable tool.

With vim-fugitive you can *commit*, *add*, *pull*, *push*, *rebase*, *blame*, *diff*, etc, without leaving Vim.
It makes a heavy use of helper buffers to facilitate the interaction with complex commands.

In this picture you can see a typical basic git workflow using some extra mappings.

![Fugitive]({{ site.url }}/assets/2015-02-09-vim-on-rails/fugitive.gif)

### Fuzzy finding

I'm not a big fan of global fuzzy finders. It's way more useful to have a quick finder
for your opened buffers. Still, a global fuzzy finder can be convenient when you're in
a project with a structure that you're not used to.

[CtrlP](https://github.com/kien/ctrlp.vim) is the *de facto* fuzzy finder for vim.
I've tried other new plugins for a while (for example Unite.vim) but CtrlP is much 
more stable and less buggy.

Some of my configuration:

	map <Leader>b :CtrlPBuffer<cr>
	let g:ctrlp_match_window_bottom   = 0
	let g:ctrlp_match_window_reversed = 0

This way you can search quickly in your buffer list using your *leader* and *b*. The other two lines are just personal
preferences (window position and file order on the list).

![CtrlP]({{ site.url }}/assets/2015-02-09-vim-on-rails/ctrlp.gif)

So, this is it for now. I hope you enjoyed this post. Try to add some of this tips
to your Rails workflow with Vim or maybe put your actual editor aside and give Vim a try :).
