# E2::UserSearch
# Jose M. Weeks <jose@joseweeks.com>
# 02 March 2003
#
# See bottom for pod documentation.

package E2::UserSearch;

use 5.006;
use strict;
use warnings;
use Carp;

use E2::Ticker;
use E2::Writeup;
use XML::Twig;

our $VERSION = "0.21";
our @ISA = qw(E2::Ticker);

sub new;
sub clear;

sub writeups;
sub sort_results;

sub new {
	my $arg   = shift;
	my $class = ref( $arg ) || $arg;
	my $self  = $class->SUPER::new();

	bless ($self, $class);

	$self->clear;

	return $self;
}

sub clear {
	my $self = shift or croak "Usage: clear E2USERSEARCH";

	$self->{lastuser} = undef;	# username of last user searched
	@{ $self->{writeups} } = ();	# list of E2::Writeup

	return 1;
}

sub writeups {
	my $self = shift or croak "Usage: writeups E2USERSEARCH [ USER ] [, SORT_BY ] [, COUNT ] [, STARTAT ]";
	my $user = shift || $self->this_username;
	my $sort_by = shift;
	my $count = shift;
	my $startat = shift;

	if( !$user ) { return undef; }

	my %options;

	$options{searchuser} = $user;
	$options{startat} = $startat	if $startat;

	if( $sort_by ) {
		$sort_by = lc($sort_by);
		if( $sort_by ne 'rep' && $sort_by ne 'creation' &&
			$sort_by ne 'title' ) {
			croak "Invalid search option: $sort_by";
		}

		$options{sort} = $sort_by;
	} else {
		$options{nosort} = 1;
		$sort_by = "none";
	}

	if( $count && $count == -1 ) { # Get all
		$options{nolimit} = 1;
	} elsif( $count ) {
		$options{count} = $count;
	}

	$user = lc( $user );

	# We don't add this search to the last if this is a
	# search on a new user.

	if( $self->{lastuser} && $self->{lastuser} ne $user ) {
		$self->clear;
	}

	# Ugly stuff, but this keeps our place so we
	# can determine the rep-based order of
	# writeups across multiple search loads.

	$self->{rep_number} = 100000 - ($startat || 0);

	# Now pass E2::Ticker::parse 'username', a 
	# twig_handler ref, and our %options

	$self->parse( 
		'usersearch',
		{ 
			'wu' => sub {
				(my $a, my $b) = @_;
				my $wu = new E2::Writeup;

				$wu->{type} = 'writeup';

				$wu->{createtime} = $b->{att}->{createtime};
				$wu->{marked}	= $b->{att}->{marked};
				$wu->{hidden}	= $b->{att}->{hidden};
				$wu->{wrtype}	= $b->{att}->{wrtype};


				$wu->{cool_count} = $b->{att}->{cools};

				if( my $rep = $b->first_child('rep') ) {
					$wu->{rep}->{up} = $rep->{att}->{up};
					$wu->{rep}->{down} = $rep->{att}->{down};
					$wu->{rep}->{total} = $rep->text;
				}
	
				if( my $lnk = $b->first_child( 'e2link' ) ) {
					$wu->{title} = $lnk->text;
					$wu->{node_id} = $lnk->{att}->{node_id};
				}

				if( my $parent = $b->first_child( 'parent' ) ) {
					my $l = $parent->first_child('e2link');
					$wu->{parent} = $l->text;
					$wu->{parent_id} = $l->{att}->{node_id};
				}

				# We're going to add a value to the E2::Writeup.
				# This is sort of a kludgy thing to do, but
				# the situation (having to infer reputation
				# based upon context) means we've got to store
				# it somewhere.

				if( $sort_by eq 'rep' ) {
					$wu->{_rep_position} = $self->{rep_number}--;
				} else {
					$wu->{_rep_position} = 0;
				}

				push @{ $self->{writeups} }, $wu;
			}
		},
		%options
	);		

	$self->{lastuser} = $user;

	return @{ $self->{writeups} };
}

sub sort_results {
	my $self = shift or croak "Usage: sort_results E2USERSEARCH [, SORTBY [ , COUNT [ , STARTAT ] ] ]";
	my $sortby = shift;
	my $count = shift;
	my $startat = shift;

	my $sort;

	# Define a bunch of sort routines

	sub sort_by_creation {
		$b->{createtime} =~ /(....)-(..)-(..) (..):(..):(..)/;
		(my $year1, my $month1, my $day1, my $hour1, my $min1, my $sec1 )
			= ($1, $2, $3, $4, $5, $6);
		$a->{createtime} =~ /(....)-(..)-(..) (..):(..):(..)/;
		(my $year2, my $month2, my $day2, my $hour2, my $min2, my $sec2 )
			= ($1, $2, $3, $4, $5, $6);

		$year1 <=> $year2 || $month1 <=> $month2 || $day1 <=> $day2 ||
			$hour1 <=> $hour2 || $min1 <=> $min2 || $sec1 <=> $sec2;
	};		

	sub sort_by_creation_reverse {
		$a->{createtime} =~ /(....)-(..)-(..) (..):(..):(..)/;
		(my $year1, my $month1, my $day1, my $hour1, my $min1, my $sec1 )
			= ($1, $2, $3, $4, $5, $6);
		$b->{createtime} =~ /(....)-(..)-(..) (..):(..):(..)/;
		(my $year2, my $month2, my $day2, my $hour2, my $min2, my $sec2 )
			= ($1, $2, $3, $4, $5, $6);

		$year1 <=> $year2 || $month1 <=> $month2 || $day1 <=> $day2 ||
			$hour1 <=> $hour2 || $min1 <=> $min2 || $sec1 <=> $sec2;
	};		

	sub sort_by_title { $a->title cmp $b->title };

	sub sort_by_title_reverse { $b->title cmp $a->title };

	sub sort_by_rep { ($b->rep->{total} || 0) <=> ($a->rep->{total} || 0) };

	sub sort_by_rep_position { $b->{_rep_position} <=> $a->{_rep_position} };

	sub sort_by_rep_position_reverse { $a->{_rep_position} <=> $b->{_rep_position} };

	sub sort_by_rep_reverse { ($a->rep->{total} || 0) <=> ($b->rep->{total} || 0) };

	sub sort_by_cools { $b->cool_count <=> $a->cool_count };

	sub sort_by_cools_reverse { $a->cools <=> $a->cools };

	sub sort_by_random{ int(rand(3))-1 };
	
	if( !$count )   { $count = -1; }
	if( !$startat ) { $startat = 0; }

	# Determine which way we want to sort and stick the method
	# into the subroutine $sort.

	if( ! defined $sortby ) {
		$sort = sub { sort_by_creation; }
	} elsif( ref( $sortby ) eq 'CODE' ) {
		$sort = $sortby;
	} elsif( lc($sortby) eq "creation" ) {
		$sort = sub { sort_by_creation; }
	} elsif( lc($sortby) eq "title" ) {
		$sort = sub { sort_by_title; }
	} elsif( lc($sortby) eq "rep" ) {
		$sort = sub { sort_by_rep || sort_by_rep_position || sort_by_creation; }
	} elsif( lc($sortby) eq "cools" ) {
		$sort = sub { sort_by_cools || sort_by_rep || sort_by_rep_position; }
	} elsif( lc($sortby) eq "creation_reverse" ) {
		$sort = sub { sort_by_creation_reverse; }
	} elsif( lc($sortby) eq "title_reverse" ) {
		$sort = sub { sort_by_title_reverse; }
	} elsif( lc($sortby) eq "rep_reverse" ) {
		$sort = sub { sort_by_rep_reverse || sort_by_rep_position_reverse ||
			sort_by_creation_reverse; }
	} elsif( lc($sortby) eq "cools_reverse" ) {
		$sort = sub { sort_by_cools_reverse || sort_by_rep_reverse ||
			sort_by_rep_position_reverse; }
	} elsif( lc($sortby) eq "random" ) {
		$sort = sub { sort_by_random; }
	} else {
		croak "Invalid sort type: $sortby";
	}

	# Sort

	my @sorted = sort $sort @{ $self->{writeups} };

	if( $count == -1 ) { return @sorted; }

	return splice @sorted, $startat, $count;
}

1;
__END__

=head1 NAME

E2::UserSearch - A module for listing and sorting a user's writeups

=head1 SYNOPSIS

	use E2::UserSearch;

	# Display homenode info

	my $user = new E2::UserSearch;

	$user->login( "Simpleton", "passwd" );	# Login so I can
						# load reps too

	# Load all writeups, unsorted.

	my @w = $user->writeups( "Simpleton", undef, -1 );

	# List the writeups

	print "All Simpleton's writeups:\n";
	print "-------------------------\n";
	foreach my $n (@w) {
		print $n->title . " : " . $n->rep->{total};
		print " : " . $n->cool_count . "C!" if $n->cool_count;
		print "\n";
	}

	# Now sort them by cools

	@w = $user->sort_results( 'cools' );

	# List the writeups

	print "\nAll Simpleton's writeups, sorted by cools:\n";
	print "------------------------------------------\n";
	foreach my $n (@w) {
		print $n->title . " : " . $n->rep->{total};
		print " : " . $n->cool_count . "C!"  if $n->cool_count;
		print "\n";
	}


=head1 DESCRIPTION

This module provides an interface to E2's user search (search for writeups by user). It inherits L<E2::Ticker|E2::Ticker>.

=head1 CONSTRUCTOR

=over

=item new

C<new> creates an C<E2::UserSearch> object.

=back

=head1 METHODS

=over

=item $user-E<gt>writeups [ USERNAME ] [, SORT_BY ] [, COUNT ] [, START_AT ]

C<writeups> does a "writeups by user" search on the user (USERNAME defaults the username of the currently-logged-in user; if no user is logged in, USERNAME must be specified or a "No username specified" error is thrown) for COUNT number of writeups (defualt is 50), starting at START_AT (which is an offset from the highest writeup as ranked by SORT_BY--more on that later), which defaults to 0. If -1 is passed as the COUNT, this method will fetch ALL writeups by the specified user. For many users, this would be a pretty big hit on the database. The suggested method is to space calls to C<writeups> over a period of time, perhaps only displaying a page at a time/etc. When you receive less writeups than you asked for, you'll have hit the final page of the writeups search.

SORT_BY can be any of 'rep', 'title', 'creation', or C<undef> (in which case, the writeups are not in any particular order). Now C<sort_results> will do client-side sorting, which at first glance would make SORT_BY = C<undef> seem the most consciencious choice (which I suppose it is), but client-side searching can not replicate all the functionality of server-side sorting for two reasons: 1) We can only sort what we have, so if we fetch the fifty most-recent writeups by a noder who's written 500, sorting them by title will yield, well, the fifty most-recent writeups by this user, sorted by title. This is quite different from what C<writeups( 'title', 50 )> would yield. And 2) most users can't sort by 'rep' client-side for any users other than themselves (they have no access to other users' reps without voting on all the writeups and then loading those writeups to fetch their rep).

C<writeups>, for all those searches called with SORT_BY = 'rep', will remember the reputation order of all writeups that it can, so if you wish to sort by 'rep' at all, I suggest you do all your searching ordered by 'rep'. I also suggest that SORT_BY = C<undef> will yield meaningless results on any client-side sorting unless a search of all the user's writeups has taken place (all at once, or over multiple calls).

C<writeups> returns a list of E2::Writeup. These do not contain doctext (C<$writeup-E<gt>text>), hold a value for C<$writeup-E<gt>cool_count> but not the (list) C<$writeup-E<gt>cools>, and may or may not have any C<$writeup-E<gt>rep> or C<$writeup-E<gt>marked> information.

Exceptions: 'Unable to process request', 'Parse error:'

=item $user-E<gt>sort_results [ SORT_BY ] [, COUNT ] [, START_AT ]

C<sort_results> sorts and returns a list of writeups (E2::Writeups) fetched from e2 by C<writeups>. COUNT is the maximum number of writeups to fetch (-1 for ALL, which is the default), START_AT is an offset from the highest ranked writeup (ranked by SORT_BY), which defaults to 0.

SORT_BY can be one of 'rep', 'title', 'creation', 'cools', or 'random', as well as 'rep_reverse', 'title_reverse', and 'creation_reverse'. It can also be a code reference which will be passed to perl's C<sort> function. A number of aliases are provided by C<sort_results>, to define particular sorting orders. For example, a 'cools' search is actually a call to C<( sort_by_cools || sort_by_rep || sort_by_rep_position )>. Each test is executed only if the test to its left returns an 'is equal' result (0).  The aliases that can be used are as follows:

	sort_by_creation;
	sort_by_creation_reverse; 
	sort_by_title;
	sort_by_title_reverse;	
	sort_by_rep;			# Sorts by known rep
	sort_by_rep_reverse;
	sort_by_rep_position;		# Sorts by implied rep (from 
	sort_by_rep_position_reverse;	# server-side 'rep' sort)
	sort_by_cools;
	sort_by_cools_reverse;
	sort_by_random;

	# Example: Sorts by cools, then title

	my @list = $user->sort_results( sub { sort_by_cools || sort_by_title } );

	# Or, sort by writeup type, then creation time.

	my @list = $user->sort_results( 
		sub { 
			$a->wrtype cmp $b->wrtype || sort_by_creation
		}
	);

C<sort_results> returns a list of E2::Writeup.  These do not contain doctext (C<$writeup-E<gt>text>), hold dummy values for C! (so C<$writeup-E<gt>cools> returns the correct value only in a scalar context), and may not have any C<$writeup-E<gt>rep> information.

Exceptions: 'Invalid sort type:'

=back

=head1 SEE ALSO

L<E2::Interface>,
L<E2::Ticker>,
L<E2::User>,
L<E2::Writeup>,
L<http://everything2.com>,
L<http://everything2.com/?node=clientdev>

=head1 AUTHOR

Jose M. Weeks E<lt>I<jose@joseweeks.com>E<gt> (I<Simpleton> on E2)

=head1 COPYRIGHT

This software is public domain.

=cut
