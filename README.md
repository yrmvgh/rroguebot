These are the guts of the Sophos IRC bot that lives on
##reddit-roguelikes on the Freenode IRC network.  The
##reddit-roguelikes channel is affiliated with the /r/roguelikes
community on Reddit <http://www.reddit.com/r/roguelikes/>. 

# Running it:
   
   Just run the boot-bot script from the bin/ directory.

# Requirements:

   - Perl 5.10.1+
   - Non-core Perl modules
       - libwww-perl
       - Class::Singleton 1.4+
       - common::sense 3.3+
       - JSON::PP 2.27104+
       - POE::Component::IRC 6.35+
       - Redis 1.904+
   - A functioning Redis 2.2.4+ server.

Requirements for running unit tests:
   - Non-core Perl modules
       - Test::MockObject
       - Test::Most

Running unit tests:

   - prove -Ilib t

To fully kill the bot, you could do something like (beware):

   `killall perl`
   `killall tail`

Note that you will need to restart the bot at 12 hours (sooner than too late), because at some point it stops logging any IRC activity.

The first run of this bot will probably spam with links. You can kill the bot and restart it. It should stop spamming.

# This bot is free software.  See the COPYING file included in this distribution for licensing terms.

Copyright (c) 2011 Colin Wetherbee <cww@denterprises.org>
