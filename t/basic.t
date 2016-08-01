use strict;
use warnings;
use Test::Deep;
use Test::More;

use lib 't/lib';

{
  package Root;
  use Moose;
  with 'Sess::Root', 'Sess::Szn::Storable';
  use namespace::autoclean;

  use Sess::Type::Hash;
  use Sess::Type::TestLogin;
  use Storable qw(nfreeze thaw);

  my $i = 'AA00';
  sub generate_id { $i++ }
  sub session_duration { 86400 }

  sub table_name { 'sessions' }

  has misc => (
    is      => 'ro',
    clearer   => 'clear_misc',
    predicate => 'has_misc',
    traits    => [ 'SessAux' ],
    handles   => [ 'payload' ],
    lazy      => 1,
    default   => sub { Sess::Type::Hash->new },
    auxclass  => 'Sess::Type::Hash',
  );

  has login => (
    is      => 'rw',
    clearer   => 'clear_login',
    predicate => 'has_login',
    traits    => [ 'SessAux' ],
    auxclass  => 'Sess::Type::TestLogin',
  );

  __PACKAGE__->meta->make_immutable;
}

sub within_one {
  abs($_[0]) <= 1;
}

subtest "absolute basics" => sub {
  my $time = time;

  my $sess = Root->new;
  isa_ok($sess, 'Root', 'our session root');

  ok(
    within_one( $sess->expires_at - ($time + 86400) ),
    "session expires about 1d hence",
  );

  like($sess->id, qr/\A[A-Z]{2}[0-9]{2}\z/, "expected-like session id");

  my $pack = $sess->pack;

  ok( ! $sess->has_misc, "packing does not create a misc aux");

  ok(exists $pack->{misc_payload}, "a full pack includes an misc_payload");
  is($pack->{misc_payload}, undef, "...and it's undef");
};

subtest "pack, unpack, pack" => sub {
  my $freeze;

  {
    my $sess = Root->new;
    isa_ok($sess, 'Root', 'our session root');

    ok(! $sess->_is_stored, "session knows it has not been stored yet");

    $sess->payload->{pies} = { apple => 1, pumpkin => 10 };

    $sess->login(
      Sess::Type::TestLogin->new({
        username   => 'rjbs',
        initial_ip => '10.23.3.201',
        initial_ua => 'rjbs/browser 1.23',
      })
    );

    my $pack = $sess->pack;

    cmp_deeply(
      $pack,
      {
        expires_at   => ignore(),
        misc_payload => { pies => { apple => 1, pumpkin => 10 } },
        login_object      => obj_isa('Sess::Type::TestLogin'),
        login_username    => 'rjbs',
        login_initial_ip  => '10.23.3.201',
        login_initial_ua  => 'rjbs/browser 1.23',
      },
      "fully-populated session packs as expected",
    );

    $freeze = Storable::nfreeze($sess->pack);
  }

  {
    my $pack = Storable::thaw($freeze);
    my $sess = Root->unpack($pack);

    ok($sess->_is_stored, "session knows it has been stored");

    cmp_deeply(
      $sess->pack,
      {
        expires_at   => ignore(),
        misc_payload => { pies => { apple => 1, pumpkin => 10 } },
        login_object      => obj_isa('Sess::Type::TestLogin'),
        login_username    => 'rjbs',
        login_initial_ip  => '10.23.3.201',
        login_initial_ua  => 'rjbs/browser 1.23',
      },
      "the session looks the same packed after freeze/thaw/unpack",
    );
  }
};

done_testing;
