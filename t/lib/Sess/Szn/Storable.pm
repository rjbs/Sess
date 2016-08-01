package Sess::Szn::Storable;
use Moose::Role;
use namespace::autoclean;

use Storable qw(nfreeze thaw);

sub freeze_refs {
  my ($self, $values) = @_;
  my @froze = map { ;  ! defined $_     ? undef
                    :    ref $_         ? (':storable:' . nfreeze($_))
                    :    /^:storable:/  ? confess("sentinel in string")
                    :                   $_ } @$values;

  return \@froze;
}

sub thaw_refs {
  my ($self, $strings) = @_;

  my @thawd = map { ;  ! defined $_     ? undef
                    :  s/^:storable://  ? (thaw($_))
                    :                   $_ } @$strings;

  return \@thawd;
}

1;
