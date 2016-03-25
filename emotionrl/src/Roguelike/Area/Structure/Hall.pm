#########################
# Area::Structure::Hall #
#########################

package Roguelike::Area::Structure::Hall;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::Tilemap;

use Exporter ();
our @ISA = ("Exporter");
our @EXPORT = do {
  no strict "refs";
  grep defined &$_, keys %{ __PACKAGE__ . "::" };
};

sub new {
  shift;  # Who cares?
  my $height = shift;
  my $width = shift;
  # Deal with the offset bug LATER.
  my $map = new Roguelike::Tilemap $height, $width, ".";
  $map->border;
  # Set map data here
  $map->{Exits} = {
    Type => "Hall",
    N => [{ Y1 => 0, Y2 => 0, X1 => 0, X2 => $width }],
    S => [{ Y1 => $height, Y2 => $height, X1 => 0, X2 => $width }],
    W => [{ Y1 => 0, Y2 => $height, X1 => 0, X2 => 0 }],
    E => [{ Y1 => 0, Y2 => $height, X1 => $width, X2 => $width }],
    Hotspots => []
  };
  $map->{Map}[ random(1, $height - 1)][ random(1, $width - 1) ]{_} = "+" if percent(5);
  if (percent(50)) {
    my ($y, $x) = ( random(1, $height - 1), random(1, $width - 1) );
    push @{ $map->{Exits}{Hotspots} }, [$y, $x] if $map->{Map}[$y][$x]{_} eq ".";
  }
  return $map;
}

42;
