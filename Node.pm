# E2::Node
# Jose M. Weeks <jose@joseweeks.com>
# 14 May 2003
#
# See bottom for pod documentation.

package E2::Node;

use 5.006;
use strict;
use warnings;
use Carp;

use E2::Interface;

our @ISA = "E2::Interface";
our $VERSION = "0.30";

# Prototypes

sub new;

sub clear;

sub title;
sub node_id;
sub author;
sub author_id;
sub createtime;
sub type;

sub bookmark;

sub load;
sub load_by_id;
sub load_from_xml;

# Object Methods

sub new {
	my $arg   = shift;
	my $class = ref( $arg ) || $arg;
	my $self  = $class->SUPER::new();

	$self->clear;

	return $self;
}

sub clear {
	my $self = shift or croak "Usage: clear E2NODE";

	$self->{title}		= undef; # Title of the node
	$self->{node_id}	= undef; # node_id
	$self->{author}		= undef; # Author (node creator)
	$self->{author_id}	= undef; # user_id of author
	$self->{time}		= undef; # Creation time
	$self->{type}		= undef; # Writeup type

	return 1;
}

sub type_as_string {
	return undef;
}

sub autodetect {
	my $self = shift or croak "Usage: autodetect E2NODE";
	bless $self, 'E2::Node';
	return 1;
}

sub load {
	my $self  = shift or croak "Usage: load E2NODE, TITLE [, TYPE]";
	my $title = shift or croak "Usage: load E2NODE, TITLE [, TYPE]";
	my $type  = shift || $self->type_as_string;

	my %opt;

	$opt{node}	  = $title;
	$opt{displaytype} = 'xmltrue';
	$opt{type}	  = $type	if $type;

	return $self->thread_then( [ \&E2::Interface::process_request, $self, %opt ],
	sub {
		my $r = shift;
		return $self->load_from_xml( $r, $type );
	});
}

sub load_by_id {
	my $self = shift or croak "Usage: load_by_id E2NODE, NODE_ID [, TYPE]";
	my $id   = shift or croak "Usage: load_by_id E2NODE, NODE_ID [, TYPE]";
	my $type = shift || $self->type_as_string;

	my %opt;

	$opt{node_id}		= $id;
	$opt{displaytype}	= 'xmltrue';
	$opt{type}		= $type		if $type;

	return $self->thread_then( [ \&E2::Interface::process_request, $self, %opt ],
	sub {
		my $r = shift;
		return $self->load_from_xml( $r, $type );
	});
}


sub load_from_xml {
	my $self = shift or croak "Usage: load_from_xml E2NODE, XML_STRING [, TYPE ]";
	my $xml	 = shift or croak "Usage: load_from_xml E2NODE, XML_STRING [, TYPE ]";
	my $type = shift || $self->type_as_string;

	my %type_to_class = (
		e2node		=> 'E2::E2Node',
		writeup 	=> 'E2::E2Node',
		user		=> 'E2::User',
		superdoc	=> 'E2::Superdoc'
	);

	# Determine what type the XML says it is.

	$xml =~ /<type>(.*?)<\/type>/s;
	my $verified_type = $1;
	
	if( !$verified_type ) {
		croak "Invalid document";
	}

	# If we hit a search page then the node doesn't exist

	if( ! ($xml =~ /<node [^>]*node_id="(.*?)"/s) ) {
		croak "Invalid document";
	}

	if( $1 == 1140332 && 				# Search node_id
	    (!$type || lc($type) ne 'superdoc') ) {
		return undef;
	}

	if( $type && lc($type) ne lc($verified_type) ) {
		return undef;
	}

	# Now, if we are an E2::Node, figure out what type of node
	# the XML is describing and bless $self into that class.

	if( ref($self) eq "E2::Node" ) {

		$self->clear;

		my $class = $type_to_class{$verified_type};
		if( !$class ) {
			croak "Invalid document";
		}

		# Convert class name to module name and
		# re-bless $self to that class.

		my $c = $class;
		$c =~ s/::/\//g;
		$c .= ".pm";

		require $c;
		bless $self, $class;

	# Otherwise, make sure the node is of the type
	# we expect.

	} else {
		if( lc($self->type_as_string) ne lc($verified_type) ) {
			croak "Wrong node type";
		}
	}

	# These are the default handlers. Descendants can add handlers by
	# returning a hash (of 'tag' => sub { ... } pairs) in the method
	# twig_handlers
	
	my %handlers = (
		'node' => sub {
			(my $a, my $b) = @_;
			$self->{node_id} = $b->{att}->{node_id};
			$self->{createtime} = $b->{att}->{createtime};
		},
		'node/type' => sub {
			(my $a, my $b) = @_;
			$self->{type} = $b->text;
		},
		'node/title' => sub {
			(my $a, my $b) = @_;
			$self->{title} = $b->text;
		},
		'node/author' => sub {
			(my $a, my $b) = @_;
			$self->{author} = $b->text;
			$self->{author_id} = $b->{att}->{user_id};
		}
	);
	
	my %h2 = $self->twig_handlers;

	if( %h2 ) {
		%handlers = ( %handlers, %h2 );  # Append twig_handlers
	}

	$self->clear;

	$self->parse_twig( $xml, \%handlers );

	return 1;
}

sub bookmark {
	my $self = shift	or croak "Usage: bookmark E2NODE [, NODE_ID ]";
	my $node_id = shift || $self->node_id;

	if( !$self->logged_in ) {
		croak "Not logged in";
	}

	if( !$node_id ) {
		croak "No node specified";
	}

	return $self->thread_then( [ \&E2::Interface::process_request, 
			$self,
			node_id		=> $node_id,
			op		=> "bookmark",
			displaytype	=> "xmltrue"
	],
	sub {
		return 1;
	});
}

#---------------
# Access methods
#---------------

sub exists {
	my $self = shift	or croak "Usage: exists E2NODE";

	if( !$self->node_id )	{ return 0; }
	else			{ return 1; }
}

sub author {
	my $self = shift	or croak "Usage: author E2NODE";

	return $self->{author};
}

sub author_id {
	my $self = shift	or croak "Usage: author_id E2NODE";

	return $self->{author_id};
}

sub node_id {
	my $self = shift	or croak "Usage: node_id E2NODE";

	return $self->{node_id};
}

sub title {
	my $self = shift	or croak "Usage: title E2NODE";

	return $self->{title}
}

sub createtime {
	my $self = shift	or croak "Usage: createtime E2NODE";

	return $self->{createtime};
}

sub type {
	my $self = shift	or croak "Usage: type E2NODE";

	return $self->{type};
}

1;
__END__
		
=head1 NAME

E2::Node - A module for loading nodes from everything2.com based on title or node_id

=head1 SYNOPSIS

	use E2::Node;

	my $node = new E2::Node;
	$node->login( "username", "password" ); # See E2::Interface

	if( $node->load( "Butterfinger McFlurry" ) ) {
		print "Title: " . $node->title;
		print "\nAuthor: " . $node->author;
		print "\nCreatetime: " . $node->createtime;
	}

	# List softlinks
	
	print "\nSoftlinks:\n";
	foreach my $s ($node->list_softlinks) {
		print $s->{title} . "\n";
	}

=head1 DESCRIPTION

This module is the base class for all e2interface modules that load data from everything2.com based on title or node_id. It allows access to the data in those nodes, and its subclasses provide data exclusive to their particular node types.

This module provides generic methods to load and parse nodes, and is also capable of detecting the type of node passed to it and re-C<bless>ing itself into the proper subclass.

This module inherits L<E2::Interface|E2::Interface>.

=head1 CONSTRUCTOR

=over

=item new

C<new> creates a new C<E2::Node> object.

=back

=head1 METHODS

=over

=item $node-E<gt>title

=item $node-E<gt>node_id

=item $node-E<gt>author

=item $node-E<gt>author_id

=item $node-E<gt>createtime

=item $node-E<gt>type

These methods return, respectively, the title of the node, the node_id, the author, the user_id of the author, the createtime (in the format "YYYY-MM-DD HH:MM:SS"), or the type, of the current node. They return C<undef> if there is no node currently loaded.

=item $node-E<gt>exists

This method returns a boolean value in answer to the question "Does this node exist?" This can be used to test whether or not a node has been loaded correctly.

=item $node-E<gt>load TITLE [, TYPE ]

=item $node-E<gt>load_by_id NODE_ID

=item $node-E<gt>load_from_xml XML_STRING

These methods load a node based upon, respectively, TITLE, NODE_ID, or XML_STRING. They populate a number of internal variables, which are accessable through the access methods listed above.

C<load_from_xml> expects to be passed an XML string of the type generated by a query to everything2.com with 'displaytype=xmltrue' set.
 
C<load> and C<load_by_id> fetch the appropriate page from everything2.com. For C<load>, if TYPE is specified, it fetches the node of that type. If no appropriate node of that type exists, they return C<undef>. Otherwise, they return true.

If the object that's doing the C<load>ing is of this class, rather than one of its descendants, the C<load> methods will attempt to determine from the XML the type of node they were passed, and then re-C<bless> the current object into that class. These are the classes an E2::Node object will be re-C<bless>ed into based on node type:

	e2node		=> E2::E2Node
	writeup		=> E2::E2Node	# NOTE: Not E2::Writeup
	user		=> E2::User
	usergroup	=> E2::Usergroup
	superdoc	=> E2::Superdoc

And here's an example:

	my $node = new E2::Node;

	# At ths point, $node is of class 'E2::Node'

	$node->load( "Brian Eno", "e2node" );

	# Now $node is of class 'E2::E2Node' and has access to
	# all the methods of that class.

Note: once an object has been re-C<bless>ed, it is a member of the new class, and therefore will generate an exception if it calls one of the C<load> methods on a different type of node.

	# (continued from above)

	$node->load( "nate", "user" ); # throws 'Wrong node type:' exception.

Once the object has been re-C<bless>ed, if we wish to autodetect node type again, we must call E2::Node->new on the object.

Exceptions: 'Unable to process request', 'Wrong node type:', 'Parse error:', 'Invalid node type:'

=back

=head1 SEE ALSO

L<E2::Interface>,
L<E2::Node>,
L<E2::E2Node>,
L<E2::Writeup>,
L<E2::Superdoc>,
L<http://everything2.com>,
L<http://everything2.com/?node=clientdev>

=head1 AUTHOR

Jose M. Weeks E<lt>I<jose@joseweeks.com>E<gt> (I<Simpleton> on E2)

=head1 COPYRIGHT

This software is public domain.

=cut
