package BDSM::DunGen::Wavey;

use strict;
use warnings;
use Util;

use base "BDSM::Map";

# TODO 1) always stable node at pivot
#      2) move up/down with you, but node is always at center. filters left/right mvs to go
#         up and down too

use constant PI => 3.14159;

sub generate {
  my ($class, $height, $width) = @_;
  ($height, $width) = (30, 75);
  
  my $map = $class->new($height, $width, " ");

  $map->{Time} = 0;
  GAME->schedule(
    -do => [$map, "sinus"],
    -id => "sin",
    -tags => ["whoknows"]
  ) if 1;

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);
  return $map;
}

# Don't expect a hanky
sub sinus {
  my $map = shift;
  $map->fill([0, 0], [$map->height, $map->width], " ");

  my $pivot = 0;

  my $here = (GAME->{Map} and GAME->{Map}{Depth} eq "Wavey");
  my $yoff = 5;
  $pivot = Player->{X} if $here;
  $yoff = Player->{Y} if $here;

  for my $x (0 .. $map->width) {
    my $y = int(5 * cos($map->{Time}) * sin( ($x - $pivot) * (2 * PI / $map->width) ));
    $map->mod($yoff - $y, $x, ".");
    #$map->mod($yoff - $y + 1, $x, ".");
    #$map->mod($yoff - $y - 1, $x, ".");
  }
  #$map->mod(5, $pivot, "~"); # The node
  #$map->border;
  #$map->_dump;

  UI->{Main}->drawme if $here;
  $map->{Time}++;
  return 0.1;
}

42;
