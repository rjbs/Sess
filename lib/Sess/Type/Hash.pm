use strict;
use warnings;
package Sess::Type::Hash;

use Moose;
use namespace::autoclean;

with 'Sess::Aux';

sub field_names { return qw(payload) }

has payload => (
  is  => 'ro',
  isa => 'HashRef',
  default => sub {  {}  },
);

sub pack {
  return {
    payload => $_[0]->payload,
  }
}

sub pack_update { $_[0]->pack }

sub unpack {
  my ($class, $data) = @_;

  return $class->new({ payload => $data->{payload} });
}

1;
