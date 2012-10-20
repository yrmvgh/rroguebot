package Bot::C::Core;

=head1 NAME

Bot::C::Core - A singleton that implements the core bot controller.

=head1 SYNOPSIS

    use Bot::C::Core;

    # Enter the application's main loop.
    Bot::C::Core->instance()->run();

=cut

use common::sense;

use base 'Class::Singleton';

use Carp;
use LWP::Simple;
use POE;
use POE::Component::IRC;
use Time::HiRes qw(time);

use Bot::M::Config;
use Bot::M::DB;
use Bot::M::Reddit;
use Bot::V::IRC;
use Bot::V::Log;

sub _ev_tick
{
    my ($self) = @_[OBJECT];

    my $target = "Sequell";
    my $msg = "!lg teamcatlobe won t turns<=246813579 s=char";

    Bot::V::Log->instance()->log("MSG_OUT($target) $msg");
    Bot::V::IRC->instance()->privmsg($target, $msg);

    my $subreddits_ref = Bot::M::Config->instance()->get_key('subreddits');

    # For each subreddit specifier, check for new posts and, if no error
    # occurred during that check, iterate over the list of returned messages
    # and send them directly to the appropriate channel.
    for my $subreddit_ref (@$subreddits_ref)
    {
        my $subreddit_name = $subreddit_ref->{subreddit};
        my $channel = $subreddit_ref->{target_channel};

        Bot::V::Log->instance()->log("Checking new [$subreddit_name] posts.");
        my $msgs_ref = Bot::M::Reddit->instance()->get_msgs($subreddit_name);

        if (defined($msgs_ref))
        {
            for my $msg (@$msgs_ref)
            {
                Bot::V::Log->instance()->log("REDDIT_OUT($channel, $msg)");
                Bot::V::IRC->instance()->privmsg($channel, $msg);
            }
        }
    }

    $_[HEAP]->{next_alarm_time} = int(time() + 300 + rand(120));
    $_[KERNEL]->alarm(tick => $_[HEAP]->{next_alarm_time});
    Bot::V::Log->instance()->log
    (
        "Set next alarm [$_[HEAP]->{next_alarm_time}]"
    );
}

# The bot is starting up.
sub _ev_bot_start
{
    my ($self) = @_[OBJECT];

    $_[HEAP]->{next_alarm_time} = int(time() + 30 + rand(45));
    Bot::V::Log->instance()->log
    (
        "Set next alarm [$_[HEAP]->{next_alarm_time}]"
    );
    $_[KERNEL]->alarm(tick => $_[HEAP]->{next_alarm_time});

    Bot::V::IRC->instance()->start_session();
}

# The bot has successfully connected to a server.  Join a channel.
sub _ev_on_connect
{
    my ($self) = @_[OBJECT];

    my $config = Bot::M::Config->instance();

    my $password = $config->get_key('irc_nickserv_password');
    Bot::V::Log->instance()->log('Identifying to NickServ');
    Bot::V::IRC->instance()->privmsg('NickServ', "identify $password");

    for my $channel (@{$config->get_key('irc_channels')})
    {
        Bot::V::Log->instance()->log("Joining channel [$channel]");
        Bot::V::IRC->instance()->join($channel);
    }
}

# Not all of these will work in PM anyways, and there is a little
# overlap with Sequell for unimportant commands.
my $FOR_HENZELL = join '|', qw(
    aplayers apt cdefine cmdinfo coffee copysave dump echo eplayers ftw
    function help idle learn macro messages nick players rc rng screensize
    seen send skill source tell time vault whereis wtf
);

# The bot has received a public message.  Parse it for commands and
# respond to interesting things.
sub _ev_on_public
{
    my ($self) = @_[OBJECT];

    my ($kernel, $who, $where, $msg) = @_[KERNEL, ARG0, ARG1, ARG2];
    my $nick    = (split /!/, $who)[0];
    my $channel = $where->[0];

    Bot::V::Log->instance()->log("MSG($channel) <$nick> $msg");

    my $config = Bot::M::Config->instance();
    my $nick = $config->get_key('irc_nick');

    if ($msg =~ /^${nick}[,:]\s*(\S.*?)\s*=\s*(\S.*?)\s*$/i ||
        $msg =~ /^\@learn\@\s*(\S.*?)\s*=\s*(\S.*?)\s*$/i)
    {
        my ($raw_key, $raw_value) = ($1, $2);

        my $msg = Bot::M::DB->instance()->add_cached($raw_key, $raw_value);

        if ($msg)
        {
            Bot::V::IRC->instance()->privmsg($channel, $msg);
        }
        else
        {
            Bot::V::Log->instance()->
            (
                "Unable to add key [$raw_key] and value [$raw_value]"
            );
        }
    }
    # Delete a key/value pair using @delete@.
    elsif ($msg =~ /^\@delete\@\s*(\S.*?)(?:\s*{(.*?)})?\s*$/i)
    {
        my ($raw_key, $raw_index) = ($1, $2);

        my $msg = Bot::M::DB->instance()->del_cached($raw_key, $raw_index);

        if ($msg)
        {
            Bot::V::IRC->instance()->privmsg($channel, $msg);
        }
        else
        {
            Bot::V::Log->instance()->
            (
                "Unable to delete key [$raw_key] at index [$raw_index]"
            );
        }
    }
    # Retrieve a key/value pair using @@ or @query@.
    elsif ($msg =~ /^\@(?:query)?\@\s*(\S.*?)(?:{(.*?)})?\s*$/i)
    {
        my ($raw_key, $raw_index) = ($1, $2);

        my $msg = Bot::M::DB->instance()->query_cached($raw_key, $raw_index);

        if ($msg)
        {
            Bot::V::IRC->instance()->privmsg($channel, $msg);
        }
        else
        {
            Bot::V::Log->instance()->
            (
                "Unable to query key [$raw_key] at index [$raw_index]"
            );
        }
    }

    my $proxies_ref = Bot::M::Config->instance()->get_key('proxies');
    for my $proxy_ref (@$proxies_ref)
    {
        my $prefix = $proxy_ref->{prefix};
        if (length($msg) >= length($prefix) &&
            substr($msg, 0, length($prefix)) eq $prefix)
        {
            my $target = $proxy_ref->{nick};
	    # special hack for henzell ! commands
	    if ($target eq "Sequell" and $msg =~ /!(?:$FOR_HENZELL)\b/) {
		$target = "Wenzell";
	    }
            Bot::V::Log->instance()->log("MSG_OUT($target) $msg");
            Bot::V::IRC->instance()->privmsg($target, $msg);
        }
    }
}

my $CLANPAGE = "http://seleniac.org/crawl/tourney/12b/clans/evilmike.html";
sub current_combos
{
    my $clandata = get($CLANPAGE);
    if (defined($clandata)) {
	my ($gamedata) = ($clandata =~ m|Ongoing Games</h3>\s*<div>\s*(.*?)\s*</div>|m);
	my @games = split /<br \/>/, $gamedata;
	my @combos = ();
	foreach my $game (@games) {
	    if (my ($combo) = ($game =~ /\(L\d+ (....)/)) {
		push @combos, $combo;
	    }
	}
	@combos = sort @combos;
	return "@combos";
    } else {
	return "unknown"
    }
}

my %RACES   = map { $_ => 1 } qw(Hu HE DE SE MD DD HO Mf Ha Ko Sp Na Ce Og Tr Mi Ke Dr Dg Ds Mu Gh Vp Fe);
my %CLASSES = map { $_ => 1 } qw(Fi Gl Mo Hu As Ar Wn Be AK CK DK Pr He Sk En Tm St Wr Wz Cj Su Ne FE IE AE EE VM);

sub compute_topic
{
    my ($msg) = @_;

    my %races   = %RACES;
    my %classes = %CLASSES;
    my ($combos) = ($msg =~ /:(.*)$/);
    foreach my $word (split / /, $combos) {
	my ($race, $class) = ($word =~ /(..)(..),?/) or next;
	delete $races{$race};
	delete $classes{$class};
    }

    return "RACES: " . (join ' ', sort { lc $a cmp lc $b } keys %races)
	. " | CLASSES: " . (join ' ', sort { lc $a cmp lc $b } keys %classes)
	. " | Ongoing games: " . current_combos();
}

sub _ev_on_msg
{
    my ($self) = @_[OBJECT];

    my ($kernel, $who, $where, $msg) = @_[KERNEL, ARG0, ARG1, ARG2];
    my $nick    = (split /!/, $who)[0];

    Bot::V::Log->instance()->log("MSG_IN($nick) $msg");

    if ($msg =~ /246813579/) {
	my $topic = compute_topic($msg);
	Bot::V::IRC->instance()->topic("##hexpistols", $topic);
	return;
    }

    my $proxies_ref = Bot::M::Config->instance()->get_key('proxies');
    for my $proxy_ref (@$proxies_ref)
    {
        if (lc($nick) eq lc($proxy_ref->{nick}))
        {
            my $channel = $proxy_ref->{target_channel};
            Bot::V::IRC->instance()->privmsg($channel, $msg);
        }
    }
}

=head1 METHODS

=cut

=head2 run()

Configures the IRC session and begins the POE kernel loop.

=cut
sub run
{
    my ($self) = @_;

    my $config = Bot::M::Config->instance();

    my $irc = POE::Component::IRC->spawn();
    Bot::V::IRC->instance()->configure($irc);

    # Set up events to handle.
    POE::Session->create
    (
        object_states =>
        [
            $self =>
            {
                _start     => '_ev_bot_start',
                irc_001    => '_ev_on_connect',
                irc_public => '_ev_on_public',
                irc_msg    => '_ev_on_msg',
                tick       => '_ev_tick',
            },
        ],
    );

    # XXX move this
    my $nick = $config->get_key('irc_nick');
    Bot::V::Log->instance()->log("Nick is $nick");

    # Run the bot until it is done.
    $poe_kernel->run();
    return 0;
}

1;

=head1 AUTHOR

Colin Wetherbee <cww@denterprises.org>

=head1 COPYRIGHT

Copyright (c) 2011 Colin Wetherbee

=head1 LICENSE

See the COPYING file included with this distribution.

=cut
