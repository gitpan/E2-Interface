# E2::Interface
# Jose M. Weeks <jose@joseweeks.com>
# 02 March 2003
#
# See bottom for pod documentation.

package E2::Interface;

use 5.006;
use strict;
use warnings;
use Carp;
use LWP::UserAgent;
use HTTP::Request::Common qw(GET HEAD POST);
use HTTP::Cookies;
use URI::Escape;
use Unicode::String;

use E2::Ticker;

our $VERSION = "0.21";

sub new;
sub clone;

sub login;
sub logout;
sub process_request;

sub domain;
sub cookie;
sub parse_links;
sub logged_in;

sub version;
sub client_name;

sub this_username;
sub this_user_id;

sub find_node_id;

# Private

sub fix_encoding;
sub process_request_raw;

# Methods

sub new {
	my $arg = shift;
	my $class = ref( $arg ) || $arg;
	my $cookie = HTTP::Cookies->new;
	my $self = {};

	bless( $self, $class );

	$self->{agent} 	= LWP::UserAgent->new( 
				agent 		=> $self->client_name . '/' .
						   $self->version,
				cookie_jar 	=> HTTP::Cookies->new
			 );

	$self->{this_username}	= 'Guest User';
	$self->{this_user_id}	= undef;
	$self->{cookie}		= undef;
	$self->{oldcookie}	= undef;

	$self->{links_noparse}	= 1;		# Don't parse links?
	$self->{domain}		= "everything2.com";

	return $self;
}

sub version {
	return $VERSION;
}

sub client_name {
	return "e2interface-perl";
}

sub clone {
	my $self  = shift	or croak "Usage: clone E2INTERFACE_DEST, E2INTERFACE_SRC";
	my $clone = shift	or croak "Usage: clone E2INTERFACE_DEST, E2INTERFACE_SRC";

	$self->{agent} 		= $clone->{agent};
	$self->{this_username}	= $clone->{this_username};
	$self->{this_user_id}	= $clone->{this_user_id};
	$self->{domain}		= $clone->{domain};
	$self->{cookie}		= $clone->{cookie};
	$self->{oldcookie}	= $clone->{oldcookie};
	
	return $self;
}

sub login {
	my $self = shift		or croak( "Usage: login E2INTERFACE, USERNAME, PASSWORD" );
	my $username = shift 		or croak( "Usage: login E2INTERFACE, USERNAME, PASSWORD" );
	my $password = shift		or croak( "Usage: login E2INTERFACE, USERNAME, PASSWORD" );

	$self->cookie( 
		"userpass=" . uri_escape "$username%7C" . crypt($password,$username)
	);

	return $self->logged_in;
}

sub logout {
	my $self = shift 	or croak "Usage: logout E2INTERFACE";

	$self->{agent}->cookie_jar->clear;

	if( $self->{cookie_file} ) {
		unlink $self->{cookie_file};
	}

	$self->{cookie} = undef;
	$self->{oldcookie} = undef;
	$self->{this_username} = 'Guest User';
	$self->{this_user_id} = undef;

	return 1;
}

sub process_request {
	my $self = shift 
		or croak "Usage: process_request E2INTERFACE, [ ATTR => VAL [ , ATTR2 => VAL2 , ... ] ]";
	my %pairs = @_
		or croak "Usage: process_request E2INTERFACE, [ ATTR => VAL [ , ATTR2 => VAL2 , ... ] ]";

	my $response = process_request_raw(
				$self->{agent}, 
				$self->{domain}, 
				"POST", 
				links_noparse => $self->{links_noparse},
				%pairs
		       );

	my $s = $response->as_string;

	# Strip HTTP headers and fix encoding

	$s =~ s/.*?\n\n//s;

	return fix_encoding( $s );
}

sub this_username {
	my $self = shift	or croak "Usage: this_username E2INTERFACE";
	return $self->{this_username};
}

sub this_user_id {
	my $self = shift	or croak "Usage: this_user_id E2INTERFACE";
	return $self->{this_user_id};
}

sub logged_in {
	my $self = shift	or croak "Usage: logged_in E2INTERFACE";

	# No cookie means we're not logged in.

	if( !$self->{cookie} ) { return 0; }

	# If we haven't already checked if we're logged in,
	# OR if the cookie has changed since we last
	# checked, check again.

	if( !$self->{oldcookie} || $self->{cookie} ne $self->{oldcookie} ) {

		my $t = new E2::Ticker;
		$t->clone( $self );

		( my $s ) = $t->time_since;	
		$self->{this_username} = $s->{name};
		$self->{this_user_id}  = $s->{id};

		if( $self->{this_username} eq 'Guest User' ) {
			$self->logout;
			return 0;
		}
	}

	# Either it checked out or we're using a cookie that's
	# still valid.

	return 1;
}

sub domain {
	my $self = shift	or croak "Usage: domain E2INTERFACE [, DOMAIN ]";
	my $dom = shift;
	
	if( $dom ) { $self->{domain} = $dom;}
	return $self->{domain};
}

sub cookie {
	my $self = shift	or croak "Usage: cookie E2INTERFACE [, COOKIE ]";
	my $cookie = shift;

	# If $cookie was passed, set the agent's cookie to $cookie.

	if( $cookie ) {

		# Make sure it's properly formatted before we
		# change it, then change it.

		$cookie =~ /^userpass=(.*$)/ or return undef;

		my $a = $1;

		$self->{agent}->cookie_jar->set_cookie( 
			0,
			'userpass',
			$a,
			'/',
			$self->domain,
			undef,
			1,
			0,
			9999999
		);

		# Here's the odd case where the cookie
		# was in the proper format but still was
		# not accepted as valid. We try to revert
		# to the former cookie, if there was one.

		if( !$self->{agent}->cookie_jar->as_string ) {
			if( $self->{cookie} && ! $self->{_recurse} ) { 
				$self->{_recurse} = 1;
				my $c = $self->cookie( $self->{cookie} );
				$self->{_recurse} = undef;
				return $c;
			}
			return undef;
		}

		$self->{cookie} = $cookie;
	}

	return $self->{cookie};
}

sub find_node_id {
	my $self = shift	or croak "Usage: find_node_id E2INTERFACE , TITLE [ , TYPE ]";
	my $title = shift	or croak "Usage: find_node_id E2INTERFACE , TITLE [ , TYPE ]";
	my $type = shift;

	if( !$type ) { $type = "e2node"; }

	my $response = $self->process_request(
				node => $title,
				type => $type,
				displaytype => "xmltrue",
				no_doctext => 1,
				nosort => 1
		       );

	if( $response =~ /<node [^>]*node_id="(.*?)"/ ) {
		if( $1 != 1140332 ) {  # Search superdoc
			return $1;
		}
		return undef;
	}

	croak "Invalid document.";
}

sub parse_links {
	my $self  = shift	or croak "Usage: parse_links E2INTERFACE [ , BOOL ]";
	
	if( @_ ) {
		my $parse = shift;
		$self->{links_noparse} = $parse ? 0 : 1;
		return 1;
	} else {
		return !$self->{links_noparse};
	}
}

# Usage: $string = fix_encoding STRING
#
# Removes smart quotes and other goodies

sub fix_encoding {
	my $s = shift	or croak "Usage: fix_encoding STRING";

	# These were stolen from a (public domain) script called
	# demoronizer.pl by John Walker (can be found at
	# http://www.fourmilab.ch/webtools/demoroniser/ ).
	# They replace MS "smart quotes" et al with stuff that won't make
	# XML parsers bitch/die/etc.

	$s =~ s/\x82/,/sg;
	$s =~ s-\x83-<em>f</em>-sg;
	$s =~ s/\x84/,,/sg;
	$s =~ s/\x85/.../sg;

	$s =~ s/\x88/^/sg;
	$s =~ s-\x89- °/°°-sg;

	$s =~ s/\x8B/</sg;
	$s =~ s/\x8C/Oe/sg;

	$s =~ s/\x91/`/sg;
	$s =~ s/\x92/'/sg;
	$s =~ s/\x93/"/sg;
	$s =~ s/\x94/"/sg;
	$s =~ s/\x95/*/sg;
	$s =~ s/\x96/-/sg;
	$s =~ s/\x97/--/sg;
	$s =~ s-\x98-<sup>~</sup>-sg;
	$s =~ s-\x99-<sup>TM</sup>-sg;

	$s =~ s/\x9B/>/sg;
	$s =~ s/\x9C/oe/sg;

	# Do some conversions to fix E2's odd character encoding  --s_alanet
	# (This is a workaround so that the parser doesn't choke.)

	my $f = Unicode::String::latin1( $s );
	$s = $f->utf8;	
	
	return $s;
}

# Usage: process_request_raw AGENT, DOMAIN, METHOD, ATTR1 => VAL1 [ , ATTR2 => VAL2 [ , ... ] ]
#
# Returns: LWP::UserAgent response object

sub process_request_raw {
	my $agent = shift or
		croak "Usage: process_request_raw AGENT, DOMAIN, METHOD, ATTR1 => VAL1 [ , ATTR2 => VAL2 [ , ... ] ]";
	my $domain = shift or
		croak "Usage: process_request_raw AGENT, DOMAIN, METHOD, ATTR1 => VAL1 [ , ATTR2 => VAL2 [ , ... ] ]";
	my $req = shift or 
		croak "Usage: process_request_raw AGENT, DOMAIN, METHOD, ATTR1 => VAL1 [ , ATTR2 => VAL2 [ , ... ] ]";

	my %pairs = @_;

	my $request;
	
	if( $req eq "POST" ) {

		$request = POST "http://$domain", [ %pairs ];

	} else {
		my $s = "http://$domain/?";
		my $prepend = "";

		foreach my $k ( keys %pairs ) {
			$s .= $prepend . uri_escape( $k ) . "=" .
				uri_escape( $pairs{$k} );
			if( !$prepend ) { $prepend = '&'; }
		}
	
		$request = HTTP::Request->new( $req => $s );
	}

	my $response = $agent->simple_request( $request );
	if( !$response->is_success ) { 
		croak "Unable to process request.";
	}
	return $response;
}

1;
__END__


=head1 NAME

E2::Interface - A client interface to the everything2.com collaborative database

=head1 SYNOPSIS

	use E2::Interface;

	my $e2 = new E2::Interface;
	$e2->set_cookie_file( "cookies.txt" );
	$e2->login( "username", "password" );

	my $page = $e2->process_request( node_id => 124, display_type => "xmltrue" );

	$e2->logout;

=head1 DESCRIPTION

=head2 Introduction

This module is the base class for e2interface, a set of modules that interface with everything2.com. It maintains an agent that connects to E2 via HTTP and that holds a persistent state (a cookie) that can be C<clone>d to allow multiple descendants of C<E2::Interface> to act a single, consistent client. It also contains a few convenience methods.

=head2 e2interface

The modules that compose e2interface are listed below and indented to show their inheritance structure.

	E2::Interface - The base module

		E2::Node	- Loads regular (non-ticker) nodes

			E2::E2Node	- Loads and manipulates e2nodes
			E2::Writeup	- Loads and manipulates writeups
			E2::User	- Loads user information
			E2::Superdoc	- Loads superdocs
			E2::Room	- Loads rooms

		E2::Ticker	- Modules for loading ticker nodes

			E2::Message	- Loads, stores, and posts messages
			E2::Search	- Title-based searches
			E2::Usersearch	- Lists and sorts writeups by a user

See the manpages of each module for information on how to use that particular module.

=head2 Error handling

e2interface uses Perl's exception-handling system, C<Carp::croak> and C<eval>. An example:

	my $int = new E2::Interface;

	print "Enter username:";
	my $name = <>; chomp $name;
	print "Enter password:";
	my $pass = <>; chomp $pass;

	eval {
		if( $int->login( $name, $pass ) ) {
			print "$name successfully logged in.";
		} else {
			print "Unable to login.";
		}
	}
	if( $@ ) {
		if $@ =~ /Unable to process request/ {
			print "Network exception: $@\n";
		} else {
			print "Unknown exception: $@\n";
		}
	}

In this case, C<login> may generate an "Unable to process request" exception if is unable to communicate with or receives a server error from everything2.com. This exception may be raised by any method in any package in e2interface that attempts to communicate with the everything2.com server.

Common exceptions include the following (those ending in ':' contain more specific data after that ':'):

	'Unable to process request' - HTTP communication error.
	'Invalid document'          - Invalid document received.
	'Parse error:'              - Exception raised while parsing
	                              document (the error output of
	                              XML::Twig::parse is placed after
	                              the ':'
	'Usage:'                    - Usage error (method called with
                                      improper parameters)

I'd suggest not trying to catch 'Usage:' exceptions: they can be raised by any method in e2interface and if they are triggered it is almost certainly due to a bug in the calling code.

All methods list which exceptions (besides 'Usage:') that they may potentially throw.

=head1 CONSTRUCTOR

=over

=item new

C<new> creates an C<E2::Interface> object. It defaults to using 'Guest User' until either C<login> or C<cookie> is used to log in a user.

=back

=head1 METHODS

=over

=item $e2-E<gt>login USERNAME, PASSWORD

This method attempts to login to Everything2.com with the specified USERNAME and PASSWORD.

This method returns true on success and C<undef> on failure.

Exceptions: 'Unable to process request'

=item $e2-E<gt>logout

C<logout> attempts to log the user out of Everything2.com. If a cookie file has been specified (with C<set_cookie_file>), the cookie file will be updated on success.

Returns true on success and C<undef> on failure.

=item $e2-E<gt>process_request ATTR1 => VAL1 [, ATTR2 => VAL2 [, ...]]

C<process_request> assembles a URL based upon the specified ATTR and VAL pairs (example: C<process_request( node_id =E<gt> 124 )> would translate to "http://everything2.com/?node_id=124" (well, technically, a POST is used rather than a GET, but you get the idea)). It requests that page via HTTP and returns the text of the response (stripped of HTTP headers and with smart quotes and other MS weirdness replaced by the plaintext equivalents). It returns C<undef> on failure.

For those pages that may be retrieved with or without link parsing (conversion of "[link]" to a markup tag), this method uses this object's C<parse_links> setting.

All necessary character escaping is handled by C<process_request>.


Exceptions: 'Unable to process request'

=item $e2-E<gt>clone OBJECT

C<clone> copies various members from the C<E2::Interface>-derived object OBJECT to this object so that both objects will use the same agent to process requests to Everything2.com. This is useful if, for example, one wants to use both an L<E2::Node|E2::Node> and an L<E2::Message|E2::Message> object to communicate with Everything2.com as the same user. This would work as follows:

	$msg = new E2::Message;
	$msg->login( $username, $password );

	$node = new E2::Node;
	$node->clone( $msg )

C<clone> returns C<$self> if successful, otherwise returns C<undef>.

=item $e2-E<gt>client_name

C<client_name> return the name of this client, "e2interface-perl".

=item $e2-E<gt>client_version

C<client_version> returns the version of this client.

=item $e2-E<gt>this_username

C<this_username> returns the username currently being used by this agent.

=item $e2-E<gt>this_user_id

C<this_user_id> returns the user_id of the current user.

=item $e2-E<gt>domain [ DOMAIN ]

If DOMAIN is specified, C<domain> sets the domain used to fetch pages to DOMAIN. DOMAIN should contain neither an "http://" or a trailing "/".

C<domain> returns the currently-used domain.

=item $e2-E<gt>cookie [ COOKIE ]

C<cookie> returns the current everything2.com cookie (used to maintain login). If COOKIE is specified, C<cookie> sets everything2.com's cookie to "COOKIE" and returns that value.

"COOKIE" is a string representing a key/value pair. Example: an account with the username "willie" and password "S3KRet" would have a cookie of "userpass=willie%257CwirQfxAfmq8I6". The implementation of the C<login> method describes how to generate a cookie... but general use requires no knowledge of this.

This is how C<cookie> would normally be used:

	# Store the cookie so we can save it to a file

	if( $e2->login( $user, $pass ) ) {
		$cookies{$user} = $e2->cookie;
	}

	...

	print CONFIG_FILE "[cookies]\n";
	foreach my $c (keys %cookies) {
		print CONFIG_FILE "$c = $cookies{$c}\n";
	}

Or:

	# Load the appropriate cookie
	
	while( $_ = <CONFIG_FILE> ) {
		chomp;
		if( /^$username = (.*)$/ ) {
			$e2->cookie( $1 );
			last;
		}
	}

If COOKIE is not valid, this function returns C<undef> and the login cookie remains unchanged.

=item $e2-E<gt>logged_in

C<logged_in> returns a boolean value, true if the user is logged in and C<undef> if not.

Exceptions: 'Unable to process request', 'Parse error:'

=item $e2-E<gt>find_node_id TITLE [, TYPE]

C<find_node_id> fetches the node_id of the node TITLE, which is of type TYPE ('e2node' by default). Returns the node_id on success and undef on failure.

Exceptions: 'Unable to process request', 'Invalid document'

=item $e2-E<gt>parse_links [BOOL]

C<parse_links> returns (and optionally sets to BOOL) an internal flag that determines, when fetching a page, whether links are parsed (converted to HTML anchor tags).

=back

=head1 SEE ALSO

L<E2::Node>,
L<E2::E2Node>,
L<E2::User>,
L<E2::Superdoc>
L<E2::Ticker>,
L<E2::Message>,
L<E2::Search>,
L<E2::UserSearch>,
L<E2::Code>,
L<E2::Nodetrack>,
L<http://everything2.com>,
L<http://everything2.com/?node=clientdev>

=head1 AUTHOR

Jose M. Weeks E<lt>I<jose@joseweeks.com>E<gt> (I<Simpleton> on E2)

=head1 COPYRIGHT

This software is public domain.

=cut
