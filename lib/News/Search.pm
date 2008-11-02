package News::Search;

use warnings;
use strict;

# @Author: Tong SUN, (c)2001-2008, all right reserved
# @Version: $Date: 2008/10/31 16:07:34 $ $Revision:  $
# @HomeURL: http://xpt.sourceforge.net/

# {{{ LICENSE: 

# 
# Permission to use, copy, modify, and distribute this software and its
# documentation for any purpose and without fee is hereby granted, provided
# that the above copyright notices appear in all copies and that both those
# copyright notices and this permission notice appear in supporting
# documentation, and that the names of author not be used in advertising or
# publicity pertaining to distribution of the software without specific,
# written prior permission.  Tong Sun makes no representations about the
# suitability of this software for any purpose.  It is provided "as is"
# without express or implied warranty.
#
# TONG SUN DISCLAIM ALL WARRANTIES WITH REGARD TO THIS SOFTWARE, INCLUDING ALL
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO EVENT SHALL ADOBE
# SYSTEMS INCORPORATED AND DIGITAL EQUIPMENT CORPORATION BE LIABLE FOR ANY
# SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER
# RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF
# CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
# CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
# 

# }}} 

# {{{ POD, Intro:

=head1 NAME

News::Search - Usenet news searching toolkit

=head1 SYNOPSIS

  use News::Search;

  my @newsgroups = ( "cups.general", "cups.bugs" );
  my %args = ( subject => 'die|break|broke' );

  my $ns = News::Search->new(\@newsgroups, \%args);
  my %newsarticles = $ns->SearchNewsgroups;

=head1 DESCRIPTION

News::Search searches Usenet news postings.

It can be used to search local news groups that google doesn't cover.
Or, even for news groups that are covered by google, it can give you
all the hits in one file, in the format that you prescribed.

You can also adapt the L<news-search> and put it into the cron job to
watch for specific news groups for specific criteria and mail you
reports according to the interval you set.

=cut

# }}}

use Carp;
use Net::NNTP;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use News::Search ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = sprintf("%d.%02d", q$Revision: 1.10 $ =~ /(\d+)\.(\d+)/);

my $NNTPSERVER = 'news';
my $HEADERS = 'Date|From';	# Subject is always returned
my $IRS = '';			# input record separator
my $Limit= 200;
my $verbose = 1;

=head1 METHODS

=head2 News::Search->new($newsgroups_array_ref, $criteria_hash_ref[, $limit])

  News::Search->new( ["cups.general", "cups.bugs"],
    { subject => 'die|break|broke' } )

criteria_hash_ref takes a hash of params, as follows:

=over 4

=item *

subject=pattern, look in the Subject: line.

=item *

from=pattern, look for author in the From: line.

=item *

body=pattern, look in article body.

=back

The above pattern match keyword can also be prefixed with 'no', e.g.,

    nosubject=pattern

to ignore messages if pattern found in the Subject: line.

=cut

sub new {
    my ($class, $newsgroups, $criteria, $limit) = @_;
    $Limit = $limit if $limit;

    my $NNTPSERVER = $ENV{"NNTPSERVER"} if $ENV{"NNTPSERVER"};

    my $nntp;
    if (defined($ENV{DEBUG}) && $ENV{DEBUG} eq "1") {
	$nntp = Net::NNTP->new($NNTPSERVER, Debug=>'On', Timeout=>10) ||
	   croak  "Cant connect to News Server: $@";
    } else {
	$nntp = Net::NNTP->new($NNTPSERVER) ||
	    croak "Cant connect to News Server: $@";
    }

    bless {
	nntp_server	=> $NNTPSERVER,
	nntp_handle	=> $nntp,
	newsgroups	=> $newsgroups,
	nntp_query	=> $criteria,
	on_group	=> \&default_group_handler,
	on_message	=> \&default_message_handler,
    } => $class;

}

# default handlers for group starts ...
sub default_group_handler {
    my $newsgroup = shift;
    #print STDERR "\n\nSearching group '$newsgroup'\n\n";
}

# default handlers for news message ...
sub default_message_handler {
    print STDERR "." if $verbose;
}

sub dbg_msg {
    my $show_msg = shift;
    my $show_level = shift;

    $show_level = 1 unless $show_level;
    return unless $verbose >= $show_level;
    warn "[News::Search] $show_msg\n";
}

=head2 SearchNewsgroups

Search the given newsgroups with the given criteria:

  my %newsarticles = $ns->SearchNewsgroups;

  foreach my $article (values %newsarticles) {
    # deal with  $article->{"SUBJECT"}, @{$article->{"HEADER"}})
    #  and $article->{"BODY"}
  }

=cut

sub SearchNewsgroups {
    my $self = shift;
    my ($newsgroups) = @_;
    $newsgroups = $self->{newsgroups} unless $newsgroups;

    my $nntp = $self->{nntp_handle};
    my $args = $self->{nntp_query};
    
    my %newsarticles;
    foreach my $newsgroup (@$newsgroups) {
	my ($first, $last) = ($nntp->group($newsgroup))[1,2];
	#warn "] $first => $last\n";
	if (($first == 0) && ($first == $last)) {
	    next;
	}

	$first = $last - $Limit if $last - $Limit > $first;
	#warn "] $first => $last\n" if $verbose;
	
	# == news article loop
	$self->{on_group}->($newsgroup);
	for ($nntp->nntpstat($first);$nntp->next() || last;) {
	    my $msghead = $nntp->head();

	    unless(defined($msghead)){
		dbg_msg "No message head found";
		next;
	    }

	    # Ignore html postings
	    if(arrary_search("Content-Type: text/html",$msghead)){
		dbg_msg "html posting ignored (found in head)";
		next;
	    }
	    
	    my ($msgfound, $msgsubj, $msgfrom, $newsarticle) =
		SearchMessage($nntp, $msghead, $args);
	    next unless $msgfound;
	    
	    $self->{on_message}->($newsgroup, $msghead, $newsarticle);

	    # Ignore html postings
	    if($newsarticle =~ "Content-Type: text/html"){
		dbg_msg "html posting ignored (found in body)";
		next;
	    }
	    
	    # zap excessive spaces
	    $newsarticle =~ s/\n(\s*\n){2,}/\n\n/;
	    # eliminate duplicated posts
	    #$newsarticles{"$msgfrom $msgsubj"} =
	    $newsarticles{"$msgfrom"} =
	    {
		"SUBJECT" => $msgsubj,
		"HEADER" => [ grep(/^($HEADERS): /, @$msghead) ],
		#"BODY" =>  $newsarticle,
		"BODY" =>  $newsarticle
		};
	}
    }
    $nntp->quit();
    return %newsarticles;
}


# message search
sub SearchMessage($$$){
    my ($nntp, $msghead, $args, ) = @_;
    my $headmatched = my $bodymatched = 0;
    my $msgfrom = "nofrom";
    my $msgsubj = "nosubj";
    my $i = 0;

    # -- message head loop
    #warn "] @$msghead\n";
    foreach my $headline (@$msghead) {
	chomp($headline);
	$headline =~ /^([^:]+): /;
	my $argname = lc $1;
	my $argval = "$'";
	$msgfrom = $argval if ($argname eq 'from');
	$msgsubj = $argval if ($argname eq 'subject');
	# look for search patterns
	if (defined($args->{$argname})) {
	    $i++;
	    if ($argval =~ m/$args->{$argname}/i) {
		#warn "] <$args->{$argname}> $argname => $argval\n";
		$headmatched = 1;
	    }
	}
	# look for ignore patterns
	if (defined($args->{"no$argname"})) {
	    if ($argval =~ m/$args->{"no$argname"}/i) {
		return (0, undef, undef, undef);
	    }
	}
    }
    $msgsubj =~ s/^\w+: //; # remove re: fw:, etc
    #warn "] headmatched = $i\n";

    if ($i == 0 && defined($args->{"body"})){
	#warn "] search in the body only\n";
	$headmatched = 1;
    }

    my $msgbodyfh = $nntp->bodyfh() || Carp::shortmess
	"Can't get body filehandle of article\n";

    # get the whole body
    my $newsarticle = '';
    while (my $bodyline=<$msgbodyfh>) {
	$newsarticle .= $bodyline;
    }
    # Ignore html postings
    #next if $newsarticle =~ m{^Content-Type: text/html|Mississauga|Scarborough|Etobicoke}mi;

    if (defined($args->{"body"})) {
	if ($newsarticle =~ m/$args->{"body"}/i) {
	    $bodymatched = 1;
	}
    } else {
	# not searching the body
	$bodymatched = 1;
    }

    return ($headmatched == 1 && $bodymatched == 1,
	    $msgsubj, $msgfrom, $newsarticle);
}

sub arrary_search($$){
    my ($look_for, $arrary_ref) = @_;
    my $is_there = 0;
    foreach my $elt (@$arrary_ref) {
        if ($elt =~ /$look_for/) {
            $is_there = 1;
            last;
        }
    }
    return $is_there;
}

1;

=head1 BUGS

Please report any bugs or feature requests to C<bug-news-search at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=News-Search>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc News::Search


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=News-Search>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/News-Search>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/News-Search>

=item * Search CPAN

L<http://search.cpan.org/dist/News-Search/>

=back


=head1 AUTHOR

SUN, Tong C<< <suntong at cpan.org> >>
http://xpt.sourceforge.net/

=head1 COPYRIGHT

Copyright 2003-2008 Tong Sun, all rights reserved.

This program is released under the BSD license.

=cut

1; # End of News::Search
