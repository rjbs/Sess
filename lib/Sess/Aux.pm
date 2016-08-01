use strict;
use warnings;
package Sess::Aux;

use Moose::Role;
use namespace::autoclean;

{
  package Sess::Attribute::SessField;
  use Moose::Role;
  Moose::Util::meta_attribute_alias('SessAux');
  no Moose::Role;
}

requires 'field_names';
requires 'pack';
requires 'pack_update';
requires 'unpack';

1;
