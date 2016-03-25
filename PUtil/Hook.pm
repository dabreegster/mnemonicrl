package PUtil::Hook;

use strict;
use warnings;

sub hook {
  my ($self, $id, $heap, $hook) = @_;
  $self->{Hooks}{$id} = [$heap, $hook];
}

sub unhook {
  my ($self, $id) = @_;
  delete $self->{Hooks}{$id};
}

# Fire callbacks, with a cooler name :)
sub hookshot {
  my ($self, @data) = @_;
  $_->[1]->($self, $_->[0], @data) foreach values %{ $self->{Hooks} };
}

42;
