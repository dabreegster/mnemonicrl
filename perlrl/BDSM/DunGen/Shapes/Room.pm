package BDSM::DunGen::Shapes::Room;

use strict;
use warnings;
use Util;

use BDSM::DunGen::Shape;
our @ISA = ("BDSM::DunGen::Shape");

# Generate a randomly shaped room.
sub room {
  my (undef, $height, $width) = @_;

  my $map = BDSM::DunGen::Shape->new($height, $width, ".");

  # A room begins its life as a normal rectangle. Then each of its four corners
  # are randomly cut out to create a unique shape.
  my ($ncut, $scut, $wcut, $ecut) = (0, 0, 0, 0);
  foreach my $corner (1 .. 4) {
    # Unless we want the bordered room to look really funky and have natural hallways
    # protruding out, we have to make sure that for each side, we leave at least 3
    # rows/columns in the middle. So our upper limit for cuts should be (side / 2) - 2.

    my $vcut = random(($height / 2) - 2);
    my $hcut = random(($width / 2) - 2);

    # Slice away!
    foreach my $y (0 .. $vcut - 1) {
      foreach my $x (0 .. $hcut - 1) {
        $map->{Map}[$y][$x]{_}           = " " if $corner == 1;
        $map->{Map}[$y][-$x - 1]{_}      = " " if $corner == 2;
        $map->{Map}[-$y - 1][$x]{_}      = " " if $corner == 3;
        $map->{Map}[-$y - 1][-$x - 1]{_} = " " if $corner == 4;
      }
    }
    
    # Emo room?!                                                          
    if ($corner == 1 or $corner == 2) {
      $ncut = $vcut if $vcut > $ncut;
    } elsif ($corner == 3 or $corner == 4) {
      $scut = $vcut if $vcut > $scut;
    }
    if ($corner == 1 or $corner == 3) {
      $wcut = $hcut if $hcut > $wcut;
    } elsif ($corner == 2 or $corner == 4) {
      $ecut = $hcut if $hcut > $ecut;
    }
  }
  $map->border;
  $map->findwalls($ncut, $scut, $wcut, $ecut);
  return $map;
}

42;
