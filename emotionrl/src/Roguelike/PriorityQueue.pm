#################
# PriorityQueue #
#################

package Roguelike::PriorityQueue;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

sub new {
  return bless [], shift;
}

sub add {
  my ($self, $element) = @_;
  push @$self, $element;
  my $i = $#{ $self };
  # Sort by priority.
  while ($i != 0) {
    # Can we swap it with $i - 1?
    if ($self->[$i]{Priority} < $self->[$i - 1]{Priority}) {
      ($self->[$i], $self->[$i - 1]) = ($self->[$i - 1], $self->[$i]);
      $i--;
    } else {
      last;
    }
  }
  return 1;
}

sub extract {
  my $self = shift;
  return undef if $#{$self} < 0;
  return shift(@$self);
}

42;
