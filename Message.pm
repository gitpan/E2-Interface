# E2::Message
# Jose M. Weeks <jose@joseweeks.com>
# 02 March 2003
#
# See bottom for pod documentation.

package E2::Message;

use 5.006;
use strict;
use warnings;
use Carp;

use E2::Ticker;

our @ISA 	= "E2::Ticker";
our $VERSION	= "0.21";

our %room_name_to_id  = (
	"outside"		=> undef, # 1102338,
	"political asylum"	=> 553129,
	"noder's nursery"	=> 553146
);

# Methods

sub new;

sub list_public;
sub list_private;

sub reset_public;
sub reset_private;

sub room;
sub room_id;
sub topic;

sub set_room;
sub send;
sub blab;
sub delete;

# Private

sub list_messages;

# Methods

sub new { 
	my $arg   = shift;
	my $class = ref( $arg ) || $arg;
	my $self  = $class->SUPER::new();
	return bless ($self, $class);
}

sub topic {
	my $self = shift	or croak "Usage: topic E2MESSAGE";
	return $self->{topic};
}

sub room {
	my $self = shift 	or croak "Usage: room E2MESSAGE";
	return $self->{room};
}

sub room_id {
	my $self = shift	or croak "Usage: room_id E2MESSAGE";
	return $self->{room_id};
}

sub reset_public {
	my $self = shift	or croak "Usage: reset_public E2MESSAGE";
	$self->{msglimit} = undef;
}

sub reset_private {
	my $self = shift	or croak "Usage: reset_private E2MESSAGE";
	$self->{p_msglimit} = undef;
}

sub list_public {
	my $self = shift	or croak "Usage: list_public E2MESSAGE";
	
	my %opt;
	
	$opt{nosort}	= 1;
	$opt{backtime}	= 10;
	$opt{msglimit}	= $self->{msglimit} if $self->{msglimit};
	$opt{for_node}	= $self->{room_id}  if $self->{room_id};
	
	# Set the internal _msglimit value to public's msglimit
	
	$self->{_msglimit} = $self->{msglimit};
	my @m = $self->list_messages( %opt );
	$self->{msglimit} = $self->{_msglimit};
	
	return @m;
}

sub list_private {
	my $self = shift	or croak "Usage: list_private E2MESSAGE [, DROP_ARCHIVED ]";
	my $drop_archived = shift;
	
	my %opt;
	
	$opt{msglimit}	= $self->{p_msglimit}	if $self->{p_msglimit};
	$opt{for_node}	= "me";
	$opt{drop_archived} = 1			if $drop_archived;

	# Set the internal _msglimit value to private's msglimit

	$self->{_msglimit} = $self->{p_msglimit};
	my @m = $self->list_messages( %opt );
	$self->{p_msglimit} = $self->{_msglimit};
	
	return @m;
}

sub list_messages {
	my $self = shift	or croak "Usage: messages E2MESSAGE [ OPTIONS ]";
	my %opt = @_;
	my $drop_archived;

	if( $opt{drop_archived} ) {
		delete $opt{drop_archived};
		$drop_archived = 1;
	}

	@{ $self->{_messages} } = ();
	$self->{topic} = undef;
	$self->{room} = undef;
	$self->{room_id} = undef;
	
	$self->parse(
		'messages',
		{
			'messages/topic' => sub { 
				(my $a, my $b) = @_;
				$self->{topic} = $b->text;
			},
			'messages/room' => sub {
				(my $a, my $b) = @_;
				$self->{room} =  $b->text;
				$self->{room_id} = $b->{att}->{room_id}
			},
			'messages/msglist/msg' => sub {
				(my $a, my $b) = @_;
				my $m = {};

				$m->{id}     = $b->{att}->{msg_id};
			
				# Set 'author' and 'author_id' if they exist

				if( my $f = $b->first_child('from') ) {
					$m->{author} = $f->first_child('e2link')->text;
					$m->{author_id} = $f->first_child('e2link')->
						{att}->{node_id};
				}

				$m->{archive} = $b->{att}->{archive};
			
				$m->{text} = $b->first_child('txt')->text;

				# Do group stuff if this is a group message

				if( my $g = $b->first_child( 'grp' ) ) {
					$m->{group} = $g->first_child('e2link')->text;
					$m->{group_id} = $g->first_child('e2link')->
						{att}->{node_id};
					$m->{grouptype} = $g->{att}->{type};
				}

				if( !$self->{_msglimit} || $m->{id} > $self->{_msglimit} ) {
					$self->{_msglimit} = $m->{id};
				}

				# Don't store if we're dropping archived AND
				# this message is archived.

				if( $drop_archived && $m->{archive} ) {
					return;
				}

				push @{ $self->{_messages} }, $m;
			}		
		},
		%opt
	);
	
	return sort { $a->{id} <=> $b->{id} } @{ $self->{_messages} };
}

sub send {
	my $self = shift		or croak "Usage: send E2MESSAGE, MESSAGE_TEXT";
	my $message = shift		or croak "Usage: send E2MESSAGE, MESSAGE_TEXT";
	
	my $response = $self->process_request(
				op		=> "message",
				message		=> $message
		       );

	if( !$response ) { return undef };

	# FIXME: Check to see if message was really sent.
	
	return 1;
}

sub set_room {
	my $self = shift	or croak "Usage: set_room E2MESSAGE, ROOM_NAME";
	my $room = shift	or croak "Usage: set_room E2MESSAGE, ROOM_NAME";

	$room = lc( $room );
	
	# Return 0 if we're already in the specified room
	
	if( lc($self->{room}) eq $room ) {
		return 0;
	}
	
	my $room_id = $room_name_to_id{$room};
	
	# If %room_name_to_id didn't contain $room, fetch it from e2

	if( !$room_id ) {
		$room_id = $self->find_node_id( $room, 'room' );
		if( !$room_id ) { return undef; }
	}

	# Now that we have the room_id, try to change rooms
	
	my $response = $self->process_request( node_id => $room_id );
	
	if( $response ) {
		# FIXME: This assumes room_id is a valid room and
		#        we have permission to enter. Prolly shouldn't.

		$self->{room} = $room;
		$self->{room_id} = $room_id;
		$self->{topic} = undef;
		$self->{msglimit} = undef;
		return 1;
	}

	return undef;
}

sub blab {

	my $self    = shift	or croak "Usage: blab E2MESSAGE, USER_ID, TEXT [ , CC_BOOL ]";
	my $user_id = shift	or croak "Usage: blab E2MESSAGE, USER_ID, TEXT [ , CC_BOOL ]";
	my $text    = shift	or croak "Usage: blab E2MESSAGE, USER_ID, TEXT [ , CC_BOOL ]";
	my $cc	    = shift;

	my %request;

	$request{node_id} = $user_id;
	$request{"msguser_$user_id"} = $text;

	if( $cc ) {
		if( !$self->{user_id} ) {
			$self->update_session;
			
			if( !$self->{user_id} ) { return undef; }
		}

		$request{"ccmsguser_" . $self->{user_id}} = 1;
	}
	
	my $response = $self->process_request( %request );

	# FIXME: Test for success.

	return 1;
}

sub delete {
	my $self = shift	or croak "Usage: delete E2MESSAGE, MSG_ID";
	my $msg_id = shift	or croak "Usage: delete E2MESSAGE, MSG_ID";

	my $response = $self->process_request( 
		"deletemsg_$msg_id"	=> "yup",
		op			=> "message"
	);

	# FIXME: Test for success.
	
	return 1;
}

1;
__END__


=head1 NAME

E2::Message - A module for accessing Everything2 messages

=head1 SYNOPSIS

	use E2::Message;

	my $catbox = new E2::Message;
	$catbox->login( "username", "password" ); # see E2::Interface
	$catbox->set_room( "Outside" );	

	# List public messages
	
	my @msg = $catbox->list_public;

	# Output the messages
	
	print "Public Messages:\n";
	print "(Topic: " . $catbox->topic . ")\n";
	foreach my $m (@msg) {
		print "$m->{author}: $m->{text}\n";
	}

	# List unarchived private messages
	
	@msg = $catbox->list_private( 1 );

	# Output the messages
	
	print "Private Messages:\n";
	foreach my $m (@msg) {
		print "($m->{group}) " if $m->{group};
		print "$m->{author}: $m->{text}\n";
	}

=head1 DESCRIPTION

This module provides an interface to L<http://everything2.com>'s messaging system (the chatterbox as well as private messages). It inherits L<E2::Ticker|E2::Ticker>.

C<E2::Message> fetches public and private messages from everything2.com. Subsequent calls to its C<list_public> and C<list_private> will return only new messages, unless the corresponding C<reset> method has been called.

=head1 CONSTRUCTOR

=over

=item new

C<new> creates an C<E2::Message> object that defaults to "Guest User" on E2 and, until C<login> is called, can retrieve only public messages and can send neither public nor private messages.

=back

=head1 METHODS

=over

=item $catbox-E<gt>topic

This method returns the current public room's topic. This topic is updated as a side-effect to both C<list_public> and C<set_room>, so if neither of these methods have been called, C<topic> will return C<undef>.

=item $catbox-E<gt>room

This method returns the current room name.

=item $catbox-E<gt>room_id

This method returns the current room's node_id.

=item $catbox-E<gt>list_public

C<list_public> fetches and returns any public messages in the current room that have been posted since the last call to C<list_public>, as well as updating the topic, room, and room_id. It returns a list of hashrefs representing the fetched messages, each with the following keys:

	author		# Username of message author
	author_id	# User_id of message author
	message_id	# Id of message
	time		# Timestamp of message
	text		# Text of the message
	
C<list_public> returns an empty list if no new messages exist.

Exceptions: 'Unable to process request', 'Parse error:'

=item $catbox-E<gt>list_private [ DROP_ARCHIVED ]

C<list_private> fetches and returns any private messages that have been posted sincethe last call to C<list_private>. If DROP_ARCHIVED is true, only messages that do not have the 'archive' flag will be returned. This method returns a list of hashrefs representing the fetched messages, each with the following keys:

	author		# Username of message author
	author_id	# User_id of message author
	id		# Id of message
	time		# Timestamp of message
	text		# Text of the message

	# The following only exist for
	# group messages

	group		# Name of usergroup 
	group_id	# Id of usergourp
	grouptype	# Type of usergroup
	
C<list_private> returns an empty list if no new messages exist.

Exceptions: 'Unable to process request', 'Parse error:'

=item $catbox-E<gt>reset_public

This method resets the public message ticker, so the next call to C<list_public> will retrieve all available public messages (they will all be considered "unfetched").

=item $catbox-E<gt>reset_private

This method resets the private message ticker, so that in the next call to C<list_private>, all private messages will be considered "unfetched."
 
=item $catbox-E<gt>send MESSAGE_TEXT

C<send> sends "TEXT" as if it were entered into E2's chatterbox. This message need not be escaped in any way. It returns true on success and C<undef> on failure.

Exceptions: 'Unable to process request'

=item $catbox-E<gt>blab RECIPIANT_ID, MESSAGE_TEXT

C<blab> sends the private "blab" message MESSAGE_TEXT to user_id RECIPIANT_ID. Returns true on success and C<undef> on failure.

Exceptions: 'Unable to process request'

=item $catbox-E<gt>delete MESSAGE_ID

C<delete> permanently deletes the private message with id MESSAGE_ID from Everything2.com. Returns true on success and C<undef> on failure.

Exceptions: 'Unable to process request'

=item $catbox-E<gt>set_room ROOM_NAME

C<set_room> changes the current public room to ROOM_NAME. It returns true on success, 0 if ROOM_NAME is already the current room, and undef on failure.

Exceptions: 'Unable to process request'

=back

=head1 SEE ALSO

L<E2::Interface>,
L<E2::Ticker>,
L<http://everything2.com>,
L<http://everything2.com/?node=clientdev>

=head1 AUTHOR

Jose M. Weeks E<lt>I<jose@joseweeks.com>E<gt> (I<Simpleton> on E2)

=head1 COPYRIGHT

This software is public domain.

=cut
