package BDSM::Toy;

use strict;
use warnings;
use Util;

sub new {
  my ($class, $map) = @_;

  my $toy = bless {}, $class;
  (my $type = $class) =~ s/^BDSM::Toy:://;
  push @{ $map->{_Data}{Toys} }, [$type];
  # When we want to delete a toy, probably want a hash so we can find this easily
  $toy->{Data} = $map->{_Data}{Toys}[-1];
  return $toy;
}

42;
