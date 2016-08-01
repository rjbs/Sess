use strict;
use warnings;
package Sess::Root;

use Moose::Role;
use namespace::autoclean;

{
  package Sess::Attribute::SessAux;
  use Moose::Role;
  Moose::Util::meta_attribute_alias('SessAux');
  has auxclass  => (is => 'ro', required => 1);
  has auxprefix => (is => 'ro', lazy => 1, default => sub { $_[0]->name });

  no Moose::Role;
}

requires 'generate_id';

has id => (
  is       => 'ro',
  # isa String / Guid / Whatever
  required => 1,
  builder  => 'generate_id',
);

has _is_stored => (
  is => 'ro',
  default => 0,
);

# * one thing to store the expires_at we had when we were instantiated
# * then we compute the new one
# * if they don't differ, then it doesn't count as dirtying the session
has original_expires_at => (
  is => 'rw',
  # isa => Maybe[PosInt]
  # required => 1,
  predicate => 'has_original_expires_at',
);

requires 'session_duration';
has expires_at => (
  is   => 'rw',
  # isa => Maybe[PosInt]
  lazy => 1,
  required => 0,
  default  => sub {
    my $original = $_[0]->original_expires_at;
    return $original if $_[0]->has_original_expires_at;
    return time + $_[0]->session_duration;
  },
);

sub extend_expiration {
  my $duration = $_[0]->session_duration;
  return unless defined $duration;
  $_[0]->expires_at( time + $duration );
}

sub is_expired {
  my ($self) = @_;

  my $expires_at = $self->expires_at;
  return unless defined $expires_at;
  return time > $self->expires_at;
}

has is_killed => (
  is     => 'ro',
  writer => '_set_is_killed',
  # isa => 'Bool'
  default => 0,
);

sub kill {
  $_[0]->_set_is_killed(1);
}

# Don't need dirty, I think.  Compute all the fields to update.  If there are
# any, then add id.
sub pack_update {
  my ($self) = @_;
  my %field;

  my $expires_at  = $self->expires_at;
  my $old_expires = $self->original_expires_at;
  if (defined $expires_at xor defined $old_expires) {
    $field{expires_at} = $expires_at;
  } elsif (defined $expires_at && $expires_at != $old_expires) {
    $field{expires_at} = $expires_at;
  }

  for my $attr (
    grep { $_->does('Sess::Attribute::SessAux') }
         $self->meta->get_all_attributes
  ) {
    my $class  = $attr->auxclass;
    my $prefix = $attr->auxprefix;
    my $update;
    if ($attr->has_value($self)) {
      my $reader = $attr->get_read_method;
      $update = $self->$reader->pack_update;
    } else {
      # anything stored in old row? if not, skip update
      $update = { map {; $_ => undef } $class->field_names };
    }

    for my $key (keys %$update) {
      # die if already set (!?)
      $field{ "$prefix\_$key" } = $update->{$key};
    }
  }

  return \%field;
}

sub pack {
  my ($self) = @_;

  my %field = (
    expires_at => $self->expires_at,
  );

  for my $attr (
    grep { $_->does('Sess::Attribute::SessAux') }
         $self->meta->get_all_attributes
  ) {
    my $class  = $attr->auxclass;
    my $prefix = $attr->auxprefix;

    my $update;
    if ($attr->has_value($self)) {
      my $reader = $attr->get_read_method;
      $update = $self->$reader->pack_update;
    } else {
      $update = { map {; $_ => undef } $class->field_names };
    }

    for my $key (keys %$update) {
      # die if already set (!?)
      $field{ "$prefix\_$key" } = $update->{$key};
    }
  }

  return \%field;
}

sub unpack {
  my ($class, $row) = @_;

  my %sess = (_is_stored => 1);
  $sess{id}         = delete $row->{id};
  $sess{is_killed}  = delete $row->{is_killed};
  $sess{original_expires_at} = delete $row->{expires_at};

  my @aux_attrs  = grep { $_->does('Sess::Attribute::SessAux') }
                        $class->meta->get_all_attributes;

  my %attr_for = map {; $_->auxprefix => $_ } @aux_attrs;

  # TODO: detect ambiguity here or below -- rjbs, 2016-07-25

  my %group;

  KEY: for my $key (keys %$row) {
    for my $prefix (keys %attr_for) {
      my $local_key = $key;
      next unless $local_key =~ s/\A\Q$prefix\E\_//;
      $group{$prefix}{$local_key} = $row->{$key};
      next KEY;
    }

    Carp::confess("unresolved pack entry $key");
  }

  for my $prefix (keys %attr_for) {
    next unless $group{$prefix};

    my $attr = $attr_for{$prefix};
    my $init = $attr->init_arg;

    # XXX die if no init arg;
    #     die if init_arg already exists in %sess -- rjbs, 2016-07-25

    my $object = $attr->auxclass->new($group{$prefix});
    $sess{$init} = $object;
  }

  return $class->new(\%sess);
}

requires 'table_name';

requires 'freeze_refs';
requires 'thaw_refs';

sub update_sql {
  my ($self) = @_;

  my $pack = $self->pack_update;

  my $tmpl = 'UPDATE %s SET %s WHERE id = ?';
  my @keys = sort keys %$pack;
  my $set  = join q{, }, map {; "$_ = ?" } @keys;
  my $sql  = sprintf $tmpl, $self->table_name, $set;

  return (
    $sql,
    $self->freeze_refs([ @$pack{ @keys } ])
  );
}

sub insert_sql {
  my ($self) = @_;

  my $pack = $self->pack;

  my $tmpl = 'INSERT INTO %s (%s) VALUES (%s)';
  my @keys = sort keys %$pack;
  my $cols = join q{, }, ('id', @keys);
  my $hook = join q{, }, ('?') x (@keys + 1);
  my $sql  = sprintf $tmpl, $self->table_name, $cols, $hook;

  return (
    $sql,
    $self->freeze_refs([ @$pack{ @keys } ])
  );
}

1;
