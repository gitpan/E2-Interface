use Test::Simple tests => 36;
use E2::Ticker;

my $t = new E2::Ticker;

open( $t->{xml_file_test}, "<t/new_writeups.xml" )
	or die "Unable to open file: $!";

ok( my @n = $t->new_writeups );
ok( $n[0]->{title} eq "idea1 (idea)" );
ok( $n[0]->{id} == 11111 );
ok( $n[0]->{type} eq "idea" );
ok( $n[0]->{author} eq "user" );
ok( $n[0]->{author_id} == 22222 );
ok( $n[0]->{parent} eq "idea1" );
ok( $n[0]->{parent_id} == 33333 );

ok( $n[1]->{title} eq "thing1 (thing)" );
ok( $n[1]->{id} == 44444 );
ok( $n[1]->{type} eq "thing" );
ok( $n[1]->{author} eq "user2" );
ok( $n[1]->{author_id} == 55555 );
ok( $n[1]->{parent} eq "thing1" );
ok( $n[1]->{parent_id} == 66666 );


open( $t->{xml_file_test}, "<t/other_users.xml" )
	or die "Unable to open file: $!";

ok( my @u = $t->other_users );
ok( $u[0]->{name} eq "Gritchka" );
ok( $u[0]->{id} == 898906 );
ok( $u[0]->{god} );
ok( ! $u[0]->{editor} );
ok( ! $u[0]->{edev} );
ok( $u[0]->{xp} == 36251 );

ok( $u[1]->{name} eq "Professor Pi" );
ok( $u[1]->{id} == 768243 );
ok( ! $u[1]->{god} );
ok( $u[1]->{editor} );
ok( $u[1]->{edev} );
ok( $u[1]->{xp} == 23896 );

ok( $u[2]->{name} eq "xunker" );
ok( $u[2]->{id} == 7515 );
ok( ! $u[2]->{god} );
ok( ! $u[2]->{editor} );
ok( $u[2]->{edev} );
ok( $u[2]->{xp} == 8136 );
ok( $u[2]->{room} eq "Noders Nursery" );
ok( $u[2]->{room_id} == 553146 );

