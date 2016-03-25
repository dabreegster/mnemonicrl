package Game::StdLib::Item::SingleUse;

use strict;
use warnings;
use Util;

use base "Game::StdLib::Item";
__PACKAGE__->announce("SingleUse");

__PACKAGE__->classdat(
  GroupBy => ["type"]
);

# We've been used, diminish our quantity.
sub destroy {
  my $self = shift;
  if ($self->{Qty} > 1) {
    $self->{Qty}--;
    return 1;
  } else {
    $self->{Owner}->del($self);
    return;
  }
}

sub name {
  my ($self, $style) = @_;
  my $name = $self->Name;
  return $name unless $style;
  if ($style eq "general") {
    if ($self->{Qty} > 1) {
      return "$self->{Qty} ${name}s";
    } else {
      return $name =~ m/^(a|e|i|o|u)/ ? "an $name" : "a $name";
    }
  } elsif ($style eq "specific") {
    return $self->{Qty} > 1 ? "$self->{Qty} ${name}s" : "the $name";
  } elsif ($style eq "inv") {
    $name = $self->{Qty} > 1 ? "$self->{Qty} ${name}s" : "$name";
    return "$self->{Index} - $name";
  }
}

package Game::StdLib::Item::SingleUse::Food;

our @ISA = ("Game::StdLib::Item::SingleUse");
__PACKAGE__->announce("Food");

__PACKAGE__->classdat(
  Category => "Food",
  Symbol   => "%",
  Verb     => "eats",
);

42;
