use strict;
use warnings;
package Sess::Type::TestLogin;

use Moose;
use namespace::autoclean;

with 'Sess::Aux';

sub field_names { return qw(username initial_ip object) }

has [ qw(username initial_ip initial_ua) ] => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

sub pack {
  return {
    (map {; $_ => $_[0]->$_ } qw(username initial_ip initial_ua)),
    object => $_[0],
  }
}

sub pack_update { $_[0]->pack }

sub unpack {
  my ($class, $data) = @_;

  return $data->{object};
}

1;
