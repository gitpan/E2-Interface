# E2::Interface
# Jose M. Weeks <jose@joseweeks.com>
# 14 May 2003
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
use XML::Twig;

use E2::Ticker;

# Threading, if supported

eval "
	use threads;
	use threads::shared;
	use Thread::Queue;
";
our $THREADED = !$@;

our $VERSION = "0.30";

# Get OS string

our $OS_STRING;

BEGIN {
	if( -x '/bin/uname' ) {
		$OS_STRING = `/bin/uname -srmo`;
		chomp( $OS_STRING );
	} else {
		$OS_STRING = $^O;
		if( $OS_STRING eq 'MSWin32' ) {
			my $s;
			eval "use Win32";
			if( !$@ ) {
				$s = join ' ', &Win32::GetOSName;
			}

			$OS_STRING = $s		if $s;
		}
	}
}

sub new;
sub clone;

sub login;
sub verify_login;
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

sub use_threads;
sub job_id;
sub thread_then;

# Private

sub post_process;
sub process_request_raw;


# Class methods

sub version {
	return $VERSION;
}

sub client_name {
	return "e2interface-perl";
}

# Object Methods

DESTROY {
	my $self = shift;

	foreach( @{$self->{threads}} ) {
		next	if ! $_->{thread}; # Why? It seems to iterate too much
		$_->{to_q}->enqueue( undef );
		$_->{thread}->detach;
	}
}

sub new {
	my $arg = shift;
	my $class = ref( $arg ) || $arg;
	my $self = {};

	# All of these are references so that we can clone()
	# copies and any changes after the cloneing affect all
	# clones.

	$self->{this_username}	= \(my $a = 'Guest User');
	$self->{this_user_id}	= \(my $b);
	
	$self->{agentstring}	= \(my $c);
	$self->{cookie}		= \(my $d);

	$self->{parse_links}	= \(my $e);
	$self->{domain}		= \(my $f = "everything2.com" );

	return bless $self, $class;
}

sub clone {
	my $self  = shift	or croak "Usage: clone E2INTERFACE_DEST, E2INTERFACE_SRC";
	my $src   = shift	or croak "Usage: clone E2INTERFACE_DEST, E2INTERFACE_SRC";

	$self->{agentstring} 	= $src->{agentstring};
	$self->{this_username}	= $src->{this_username};
	$self->{this_user_id}	= $src->{this_user_id};
	$self->{parse_links}	= $src->{parse_links};
	$self->{domain}		= $src->{domain};
	$self->{cookie}		= $src->{cookie};

	return $self;
}

sub login {
	my $self = shift		or croak( "Usage: login E2INTERFACE, USERNAME, PASSWORD" );
	my $username = shift 		or croak( "Usage: login E2INTERFACE, USERNAME, PASSWORD" );
	my $password = shift		or croak( "Usage: login E2INTERFACE, USERNAME, PASSWORD" );

	return $self->thread_then(
		[ 
			\&process_request,
			$self,
			op   => 'login',
			user => $username,
			passwd => $password,
			node => $E2::Ticker::xml_title{session}
		],
	sub {

		my $xml = shift;

		if( $xml =~ /<currentuser .*?user_id="(.*?)".*?>(.*?)</s ) {
			${$self->{this_username}} = $2;
			${$self->{this_user_id}}  = $1;
		} else {
			croak "Invalid document";
		}

		return $self->cookie && 1;	
	});
}

sub verify_login {
	my $self = shift;

	return undef	if !$self->logged_in;

	return $self->thread_then(
		[
			\&process_request,
			$self,
			node => $E2::Ticker::xml_title{session}
		],
	sub {
		my $xml = shift;
	
		if( $xml =~ /<currentuser .*?user_id="(.*?)".*?>(.*?)</s ) {
			${$self->{this_username}} = $2;
			${$self->{this_user_id}}  = $1;
		} else {
			croak "Invalid document";
		}

		return $self->cookie && 1;
	});
}

sub logout {
	my $self = shift 	or croak "Usage: logout E2INTERFACE";

	$self->cookie( undef );
	${$self->{this_username}} = 'Guest User';
	${$self->{this_user_id}}  = undef;

	return 1;
}

sub process_request {
	my $self = shift 
		or croak "Usage: process_request E2INTERFACE, [ ATTR => VAL [ , ATTR2 => VAL2 , ... ] ]";
	my %pairs = @_
		or croak "Usage: process_request E2INTERFACE, [ ATTR => VAL [ , ATTR2 => VAL2 , ... ] ]";

# If we're dealing with threads, send a process_request message

	if( $self->{threads} ) {
		$self->start_job(
			'POST',
			'http://' . $self->domain . '/',
			$self->cookie,
			${$self->{agentstring}},
			($self->parse_links ? () : (links_noparse => 1)),
			%pairs
		);

		return -1;
	}

	# Otherwise, just process the request

	my $response = process_request_raw(
				'POST',
				'http://' . $self->domain . '/', 
				$self->cookie,
				${$self->{agentstring}},
				($self->parse_links?():(links_noparse => 1)),
				%pairs
		       );

	my $c = extract_cookie( $response );
	$self->cookie( $c )	if $c;

	return $self->{last_document} = post_process( $response );
}

sub this_username {
	my $self = shift	or croak "Usage: this_username E2INTERFACE";
	return ${$self->{this_username}};
}

sub this_user_id {
	my $self = shift	or croak "Usage: this_user_id E2INTERFACE";
	return ${$self->{this_user_id}};
}

sub logged_in {
	my $self = shift	or croak "Usage: logged_in E2INTERFACE";

	return ${$self->{cookie}} && 1;
}

sub domain {
	my $self = shift     or croak "Usage: domain E2INTERFACE [, DOMAIN ]";
	
	${$self->{domain}} = $_[0]	if $_[0];
	
	return ${$self->{domain}};
}

sub cookie {
	my $self = shift  or croak "Usage: cookie E2INTERFACE [, COOKIE ]";

	if( @_ ) {
		${$self->{cookie}} = $_[0];

		if( $_[0] =~ /(.*?)%257C/ ) {
			$self->{this_username} = $1;
		}
	}

	return ${$self->{cookie}};
}

sub agentstring {
	my $self = shift  or croak "Usage: agentstring E2INTERFACE [, STRING ]";

	${$self->{agentstring}} = $_[0]	if @_;

	return ${$self->{agentstring}};
}

sub parse_links {
	my $self = shift  or croak "Usage: parse_links E2INTERFACE [ , BOOL ]";

	${$self->{parse_links}} = $_[0]	if @_;

	return ${$self->{parse_links}};
}

sub document {
	my $self = shift  or croak "Usage: xml E2INTERFACE";

	return $self->{last_document};
}

sub parse_twig {
	if( @_ != 3 ) { croak "Usage: parse_twig E2INTERFACE, XML, HANDLERS"; }
	
	my ( $self, $xml, $handlers ) = @_;

	my $twig = new XML::Twig(
		keep_encoding => 1, 
		twig_handlers => $handlers
	);
	
	if( !$twig->safe_parse( $xml ) ) {
		chomp $@;
		croak "Parse error: $@";
	}
}

sub use_threads {
	my $self = shift   or croak "Usage: use_threads E2INTERFACE [, COUNT ]";
	my $count = shift || 1;

	return undef	if !$THREADED;	
	return undef	if $count < 1;
	return undef	if $self->{threads};

	$self->{next_job_id} = 1;

	@{$self->{threads}} = ();
	for( my $i = 0; $i < $count; $i++ ) {
		my %t = (
			to_q	=> Thread::Queue->new,
			from_q	=> Thread::Queue->new,
		);
		
		$t{thread} = threads->create(
			\&_thread,
			$t{to_q},
			$t{from_q}
		);

		push @{$self->{threads}}, \%t;
	}

	return 1;


	sub _thread {
		my $from_q = shift;
		my $to_q   = shift;
		my $id;
		
		while( $id = $from_q->dequeue ) {
			my $req = $from_q->dequeue;
			my $resp;
			my %r : shared;

			eval { $resp = process_request_raw( @$req ) };
			if( $@ ) {
				$r{exception} = $@;
			} else {
				$r{cookie} = extract_cookie( $resp );
				$r{text}   = post_process( $resp );
			}
			
			$to_q->enqueue( $id, \%r );
		}
	}
}

sub job_id {
	my $self = shift	or croak "Usage: job_id E2INTERFACE";

	return $self->{job};
}

sub thread_then {
	my $self = shift;
	my $cmd  = shift;
	my $post = shift;
	
	my @response;

	# Run command. If not threaded, run its post command and
	# return

	if( ref $cmd ) {
		my $c = shift @$cmd;
		@response = &$c( @$cmd );
	} else {
		@response = &$cmd( @_ );
	}
	
	if( $response[0] ne "-1" ) {
		return &$post( @response );
	}

	# If we're here, we called a threaded routine. Add the post
	# command to its caller's list

	my $id = $self->job_id;
	push @{$self->{post_commands}->{$id}}, $post;
	
	return -1;
}

sub finish {
	my $self = shift;
	my $job = shift;

	my $response;

	# First, check to see if we've already pulled this job off the
	# queue.

	if( $self->{finished}->{$job} ) {
		$response = $self->{finished}->{$job};
		delete $self->{finished}->{$job};
	}	

	# Otherwise, get it off the queue (if we can)

	else {	
		my $thr = $self->{job_to_thread}->{$job};
		return undef if !$thr;

		while( my $id = $thr->{from_q}->dequeue_nb ) {

			# Get response

			my $r = $thr->{from_q}->dequeue;
		
			if( $id == $job ) {	# The right job?
				$response = $r;
				last;
			} else {
				# Store for later
				$self->{finished}->{$id} = $r;
			}
		}
		
		# Now, if the job is complete, $response will contain
		# a value. If it doesn't, return -1 and set job_id
		# (tell the caller that the command is still deferred).

		if( ! $response ) {
			$self->{job} = $job;
			return -1;
		}
	}

	# If we've received an exception, now is the time to
	# throw it.

	if( $response->{exception} ) {
		croak $response->{exception};
	}	

	# Now, finish the command and return

	$self->cookie( $response->{cookie} ) if $response->{cookie};

	# Save document

	$self->{last_document} = $response->{text};

	# Execute any post code, passing the return values of one
	# as the parameters of the next
	
	my @param = ( $response->{text} );
	my @ret   = ( $response->{text} );
	
	while( my $c = shift @{$self->{post_commands}->{$job}} ) {
		@ret = &$c( @param );
		@param = @ret;
	}
	
	delete $self->{post_commands}->{$job};
	
	return ( $job, @ret );
}

sub start_job {
	my $self = shift;

	# Find the first open thread, or the one with the
	# least jobs pending.

	my $min = 9999;
	my $thr = $self->{threads}->[0];

	foreach( @{$self->{threads}} ) {
		if( !$_->{to_q}->pending ) {
			$thr = $_;
			last;
		} elsif( $_->{to_q}->pending < $min ) {
			$min = $_->{to_q}->pending;
			$thr = $_;
		}
	}

	# Send the message

	$self->{job} = $self->{next_job_id}++;
	my @job : shared = @_;

	$thr->{to_q}->enqueue( $self->{job}, \@job );

	$self->{job_to_thread}->{$self->{job}} = $thr;

	return -1;
}

sub extract_cookie {
	my $response = shift;
	my $c = new HTTP::Cookies;
	$c->extract_cookies( $response );
	$c->as_string =~ /userpass=(.*?);/;
	if( $1 && $1 eq '""' ) { return undef; } # Sometimes the server returns
	                                         # userpass=""; if so, discard
	return $1;
}

# Usage: $string = post_process STRING
#
# Turns the return value of process_request_raw into a
# string. Fixes encoding as well.

sub post_process {
	my $resp = shift	or croak "Usage: post_process RESPONSE";

	my $s = $resp->as_string;

	# Strip HTTP headers

	$s =~ s/.*?\n\n//s;

	# Fix encoding

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

# Usage: process_request_raw METHOD, URL, COOKIE, AGENTSTR [, ATTR_PAIRS ... ]
# 	METHOD is one of 'GET', 'POST', 'HEAD', etc.
# 	URL is the base url of the request (the part before the '?')
# 	COOKIE is an attribute=value pair to be used as a cookie
# 	AGENTSTR is the agent string to be used for the request
# 	ATTR_PAIRS is a set of list of attribute=value pairs to be
# 	           used to fetch the url.
# Returns: a LWP::UserAgent response object

sub process_request_raw {
	if( @_ < 3 ) { 
		croak "Usage: process_request_raw" .
		      "METHOD, URL, COOKIE, AGENTSTR [, ATTR_PAIRS ]";
	}
	
	my $req		= shift;
	my $url		= shift;
	my $cookie	= shift;
	my $agentstr	= shift;
	my %pairs = @_;

	my $str = client_name . '/' . version . " ($OS_STRING)";
	$str = "$agentstr $str" if $agentstr;
	
	my $agent = LWP::UserAgent->new(
		agent		=> $str,
		cookie_jar	=> HTTP::Cookies->new
	);
	
	if( $cookie ) {
		$url =~ m-//(.*?)/-;	# extract domain
		
		$agent->cookie_jar->set_cookie( 
			0,
			'userpass',
			$cookie,
			'/',
			$1,
			undef,
			1,
			0,
			9999999
		);
	}

	my $request;

	if( $req eq "POST" ) {

		$request = POST $url, [ %pairs ];

	} else {
	
		my $s = "$url?";
		my $prepend = "";

		foreach( keys %pairs ) {
			$s .= $prepend . uri_escape( $_ ) . "=" .
				uri_escape( $pairs{$_} );
			if( !$prepend ) { $prepend = '&'; }
		}
	
		$request = HTTP::Request->new( $req => $s );
	}

	my $response = $agent->simple_request( $request );
	if( !$response->is_success ) { 
		croak "Unable to process request";
	}
	return $response;
}

1;
__END__


=head1 NAME

E2::Interface - A client interface to the everything2.com collaborative database

=head1 SYNOPSIS

	use E2::Interface;
	use E2::Message;

	# Login

	my $e2 = new E2::Interface;
	$e2->login( "username", "password" );

	# Print client information

	print "Info about " . $e2->client_name . "/" . $e2->version . ":";
	print "\n  domain:     " . $e2->domain";
	print "\n  cookie:     " . $e2->cookie";
	print "\n  parse links:" . ($e2->parse_links ? "yes" : "no");
	print "\n  username:   " . $e2->this_username;
	print "\n  user_id:    " . $e2->this_userid;

	# Load a page from e2	

	my $page = $e2->process_request( 
		node_id => 124,
		display_type => "xmltrue"
	);

	# Now send a chatterbox message using the current
	# settings of $e2

	my $msg = new E2::Message;
	$msg->clone( $e2 );

	$msg->send( "This is a message" ); # See E2::Message

	# Logout

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
			E2::Room	- Loads room information
			E2::Usergroup	- Loads usergroup information

		E2::Ticker	- Modules for loading ticker nodes

			E2::Message	- Loads, stores, and posts msgs
			E2::Search	- Title-based searches
			E2::Usersearch	- Search for writeups by user
			E2::Session	- Session information
			E2::ClientVersion - Client version information

See the manpages of each module for information on how to use that particular module.

=head2 Error handling

e2interface uses Perl's exception-handling system, C<Carp::croak> and C<eval>. An example:

	my $e2 = new E2::Interface;

	print "Enter username:";
	my $name = <>; chomp $name;
	print "Enter password:";
	my $pass = <>; chomp $pass;

	eval {
		if( $e2->login( $name, $pass ) ) {
			print "$name successfully logged in.";
		} else {
			print "Unable to login.";
		}
	};
	if( $@ ) {
		if $@ =~ /Unable to process request/ {
			print "Network exception: $@\n";
		} else {
			print "Unknown exception: $@\n";
		}
	}

In this case, C<login> may generate an "Unable to process request" exception if it's unable to communicate with or receives a server error from everything2.com. This exception may be raised by any method in any package in e2interface that attempts to communicate with the everything2.com server.

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

=head2 Threading

Network access is slow. Methods that rely upon network access may hold control of your program for a number of seconds, perhaps even minutes. In an interactive program, this sort of wait may be unacceptable.

e2interface supports a limited form of multithreading (in versions of perl that support ithreads--i.e. 5.8.0 and later) that allows network-dependant members to be called in the background and their return values to be retrieved later on. This is turned on by calling C<use_threads> on an instance of any class derived from E2::Interface. After doing so, any method that relies on network access will return -1 and be executed in the background.

The id of the background job can then be retrieved by calling C<job_id>, and the return value can be retrieved by passing the id to C<finish>. If the method has not yet completed, C<finish> returns -1. If the method has completed, C<finish> returns a list consisting of the job_id followed by the return value of the method.

A code reference can be also be attached to a background method. See C<thread_then>.

A simple example of threading in e2interface:

	use E2::Message;

	my $catbox = new E2::Message;

	$catbox->use_threads;	# Turn on threading

	my @r = $catbox->list_public; # This will run in the background
	my $id = $catbox->job_id;

	while( $r[0] eq "-1" ) { # While method deferred (use a string
				 # comparison--if $r[0] happens to be
				 # a string, you'll get a warning when
				 # using a numeric comparison)

		# Do stuff here........

		@r = $catbox->finish( $id );
	}

	# Once we're here, @r contains: ( job_id, return value )

	shift @r;			# Discard the job_id

	foreach( @r ) {	
		print $_->{text};	# Print out each chatterbox message
	}

Or, the same thing could be done using C<thread_then>:

	use E2::Message;

	my $catbox = new E2::Message;

	$catbox->use_threads;

	# Execute $catbox->list_public in the background

	$catbox->thread_then( [ \&E2::Message::list_public ],

		# This subroutine will be called when list_public finishes,
		# and will be passed its return value in @_

		sub {
			foreach( @_ ) {
				print $_->{text};
			}

			# If we were to return something here, it could
			# be retrieved in the call to finish() below.
		}
	);

	my $id = $catbox->job_id;

	# Do stuff here.....

	# Discard the return value of the deferred method (this will be
	# the point where the above anonymous subroutine actually
	# gets executed, during a call to finish())

	while( $node->finish ) {} # Finish will not return a false
				  # value until all deferred methods
				  # have completed 

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

Exceptions: 'Unable to process request', 'Invalid document'

=item $e2-E<gt>verify_login

This method can be called after setting C<cookie>; it (1) verifies that the everything2 server accepted the cookie as valid, and (2) determines the user_id of the logged-in user, which would otherwise be unavailable.

=item $e2-E<gt>logout

C<logout> attempts to log the user out of Everything2.com.

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

C<clone> copies the cookie, domain, parse_links value, and agentstring, and it does so in such a way that if any of the clones (or the original) change any of these values, the changes will be propogated to all the others.

C<clone> returns C<$self> if successful, otherwise returns C<undef>.

=item $e2-E<gt>client_name

C<client_name> return the name of this client, "e2interface-perl".

=item $e2-E<gt>version

C<version> returns the version number of this client.

=item $e2-E<gt>this_username

C<this_username> returns the username currently being used by this agent.

=item $e2-E<gt>this_user_id

C<this_user_id> returns the user_id of the current user. This is only available after C<login> or C<verify_login> has been called (in this instance or another C<clone>d instance).

=item $e2-E<gt>domain [ DOMAIN ]

If DOMAIN is specified, C<domain> sets the domain used to fetch pages to DOMAIN. DOMAIN should contain neither an "http://" or a trailing "/".

C<domain> returns the currently-used domain.

=item $e2-E<gt>cookie [ COOKIE ]

C<cookie> returns the current everything2.com cookie (used to maintain login). If COOKIE is specified, C<cookie> sets everything2.com's cookie to "COOKIE" and returns that value.

"COOKIE" is a string value of the "userpass" cookie at everything2.com. Example: an account with the username "willie" and password "S3KRet" would have a cookie of "willie%257CwirQfxAfmq8I6". This is generated by the everything2 servers.

This is how C<cookie> would normally be used:

	# Store the cookie so we can save it to a file

	if( $e2->login( $user, $pass ) ) {
		$cookies{$user} = $e2->cookie;
	}

	...

	print CONFIG_FILE "[cookies]\n";
	foreach( keys %cookies ) {
		print CONFIG_FILE "$_ = $cookies{$_}\n";
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

=item $e2-E<gt>agentstring

C<agentstring> returns and optionally sets the value prependend to e2interface's agentstring, which is then used in HTTP requests.

=item $e2-E<gt>document

C<document> returns the text of the last document retrieved by this instance in a call to C<process_request>.

Note: if threading is turned on, this is updated by a call to C<finish>, and will refer to the document from the most recent method C<finish>ed.

=item $e2-E<gt>logged_in

C<logged_in> returns a boolean value, true if the user is logged in and C<undef> if not.

Exceptions: 'Unable to process request', 'Parse error:'

=item $e2-E<gt>use_threads [ NUMBER ]

C<use_threads> creates a background thread (or NUMBER background threads) to be used to execute network-dependant methods. These are specific to their particular instance (i.e. they can't be C<clone>d). This method can only be called once for any instance, and once threading has been enabled, it can't be disabled again.

C<use_threads> returns true on success and C<undef> on failure.

=item $e2->E<gt>job_id

C<job_id> returns the job_id of the most recently deferred method.

=item $e2-E<gt>finish [ JOB_ID ]

C<finish> handles all post-processing of deferred methods (see C<thread_then> for information on adding post-processing to a method), and attempts to return the return value of a deferred method. If JOB_ID is specified, it attempts to return the return value of that method, otherwise it attempts to return the return value of the first completed method on its queue.

It returns a list consisting of the job_id of the deferred method followed by the return value of the method in list context. If JOB_ID is specified and the corresponding method is not yet completed, this method returns -1. If JOB_ID is not specified, and there are methods left on the deferred queue but none of them are completed, it returns -1. It returns C<undef> if the deferred queue is empty.

=item $e2-E<gt>thread_then METHOD, CODE

C<thread_then> executes METHOD (which is a reference to an array that consists of a method and its parameters, e.g.: [ \&E2::Node::load, $title, $type ]), and sets up CODE (a code reference) to be passed the return value of METHOD when METHOD completes.

C<thread_then> is named as a sort of mnemonic device: "thread this method, then do this..."

C<thread_then> returns -1 if METHOD is deferred; if METHOD is not deferred, thread_then immediately passes its return value to CODE and then returns the return value of CODE. This allows code to be written that can be run as either threaded or unthreaded; indeed this is how e2interface is implemented internally.

=back

=head1 SEE ALSO

L<E2::Node>,
L<E2::E2Node>,
L<E2::Writeup>,
L<E2::User>,
L<E2::Superdoc>
L<E2::Usergroup>
L<E2::Room>
L<E2::Ticker>,
L<E2::Message>,
L<E2::Search>,
L<E2::UserSearch>,
L<E2::ClientVersion>,
L<E2::Session>
L<http://everything2.com>,
L<http://everything2.com/?node=clientdev>

=head1 AUTHOR

Jose M. Weeks E<lt>I<jose@joseweeks.com>E<gt> (I<Simpleton> on E2)

=head1 COPYRIGHT

This software is public domain.

=cut
