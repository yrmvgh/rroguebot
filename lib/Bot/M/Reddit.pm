package Bot::M::Reddit;

=head1 NAME

Bot::M::Reddit - A singleton that implements the ability to check Reddit for
new posts in a specific subreddit.

=head1 SYNOPSIS

    use Bot::M::Reddit;
    use Bot::V::IRC;

    my $msgs_ref = Bot::M::Reddit->instance()->get_msgs('steampunk');
    if (defined($msgs_ref))
    {
        for my $msg (@$msgs_ref)
        {
            Bot::V::IRC->instance()->privmsg('#steampunk', $msg);
        }
    }

=cut

use common::sense;

use base 'Class::Singleton';

use JSON::PP;
use LWP::UserAgent;

use Bot::M::DB;
use Bot::V::Log;

sub _new_instance
{
    my $ua = LWP::UserAgent->new();
    $ua->timeout(4);
    my $json = JSON::PP->new();

    my %self =
    (
        ua   => $ua,
        json => $json,
    );

    bless \%self, shift;
}

sub _reddit_new_url
{
    my ($self, $subreddit) = @_;

    return undef unless $subreddit;
    return "http://www.reddit.com/r/$subreddit/new/.json";
}

=head1 METHODS

=cut

=head2 get_msgs($subreddit)

Retrieves the latest posts from the $subreddit subreddit, formats them into
messages suitable for sending directly to an IRC user or channel, and returns
an array ref containing those messages.  Returns undef on error (e.g. if
Reddit is down, etc.).

=cut
sub get_msgs
{
    my ($self, $subreddit) = @_;

    my $url = $self->_reddit_new_url($subreddit) or return;

    Bot::V::Log->instance()->log("Requesting URL [$url]");

    my $r = $self->{ua}->get($url);

    if ($r and $r->is_success)
    {

        my $db = Bot::M::DB->instance();
        my @links = eval {
            my $listing   = $self->{json}->decode($r->decoded_content);
            my @all_links = map $_->{data}, @{ $listing->{data}{children} };

            # For each link we found, get the vital information store it for
            # later.  Don't record links we've already seen or links that do
            # not match the Reddit entity ID whitelist pattern.
            my @new_links = grep {
              $_->{id} and !$db->have_seen('reddit', $_->{id})
            } @all_links;

            $db->add_seen('reddit', map $_->{id}, @new_links);

            map +{
                id     => $_->{id},
                url    => "http://redd.it/$_->{id}",
                author => $_->{author},
                title  => $_->{title} =~ tr/\n//dr,
            }, @new_links;
        };

        if ($@) {
            Bot::V::Log->instance()->log("Unable to parse Reddit JSON: $@");
            return;
        }

        return [
          map sprintf(
            '%s: %s | /r/%s | %s', @$_{qw(author title)}, $subreddit, $_->{url}
          ), @links
        ];
    }
    else
    {
        Bot::V::Log->instance()->log
        (
            "Reddit request for subreddit [$subreddit] did not succeed"
        );
        return;
    }
}

1;

=head1 AUTHOR

Colin Wetherbee <cww@denterprises.org>

=head1 COPYRIGHT

Copyright (c) 2011 Colin Wetherbee

=head1 LICENSE

See the COPYING file included with this distribution.

=cut
