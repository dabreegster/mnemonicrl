#########################
# Area::Structure::Room #
#########################

package Roguelike::Area::Structure::Room;

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
  my ($ncut, $scut, $wcut, $ecut) = (0, 0, 0, 0);
  foreach my $corner (1 .. 4) {
    if (percent 50) {
      my $vcut = random($map->height / 2);
      my $hcut = random($map->width / 2);
      foreach my $y (0 .. $vcut - 1) { 
        foreach my $x (0 .. $hcut - 1) {
          $map->{Map}[$y][$x]{_} = " " if $corner == 1;
          $map->{Map}[$y][-$x - 1]{_} = " " if $corner == 2;
          $map->{Map}[-$y - 1][$x]{_} = " " if $corner == 3;
          $map->{Map}[-$y - 1][-$x - 1]{_} = " " if $corner == 4;
        }
      }
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
  }
  $map->border;
  findwalls($map, $ncut, $scut, $wcut, $ecut);
  # Hawt spots
  $map->{Exits}{Hotspots} = [];
  {
    my $dat = chooserand(@{ $map->{Exits}{N} });
    my $y = $dat->{Y1} + random(1, 4);  # TWEAKYWEAKYWOOOOOOOOOOOOO
    my $x = random($dat->{X1} + 1, $dat->{X2} - 1);
    next if $y > $map->height or $y < 0;
    next if $x > $map->width or $x < 0;
    push @{ $map->{Exits}{Hotspots} }, [$y, $x] if $map->{Map}[$y][$x]{_} eq ".";
  }
  {
    my $dat = chooserand(@{ $map->{Exits}{W} });
    my $y = random($dat->{Y1} + 1, $dat->{Y2} - 1);
    my $x = $dat->{X1} + random(1, 4);  # TWEAKYWEAKYWOOOOOOOOOOOOO
    next if $y > $map->height or $y < 0;
    next if $x > $map->width or $x < 0;
    next unless defined $map->{Map}[$y][$x];
    push @{ $map->{Exits}{Hotspots} }, [$y, $x] if $map->{Map}[$y][$x]{_} eq ".";
  }
  return $map;
}

sub findwalls {
  my $self = shift;
  my ($ncut, $scut, $wcut, $ecut) = @_;
  my $data = { N => [], S => [], W => [], E => [] };
  # Northern wall
  foreach my $y (0 .. $ncut) {
    # Loop through the row. Keep a counter of how many consecutive wall tiles
    # occur with nothing above them. Store the first coordinate and the last
    # coordinate. When blank space or a floor tile is reached, add the wall if
    # it was long enough.
    my $cnt = 0;
    my $x1 = 0;
    my $x2 = 0;
    my $mode = 0; # One when we've got a wall
    foreach my $x (0 .. $self->width) {
      if ($self->{Map}[$y][$x]{_} eq "#") {
        next if $y != 0 and $self->{Map}[$y - 1][$x]{_} ne " ";
        $x1 = $x if $mode == 0; # Is this our first tile?
        $mode = 1;  # Inevitably
        $x2 = $x;
        $cnt++;
      } else {
        if ($mode == 1) {
          # Woo! We might have a valid wall.
          push @{ $data->{N} }, [ $y, $x1, $y, $x2 ] if $cnt >= 3;
          # Clear things.
          $cnt = $mode = $x1 = $x2 = 0;
        } else {
          next;
        }
      }
    }
    # Now see if there's anything stored up that hasn't been processed.
    push @{ $data->{N} }, [ $y, $x1, $y, $x2 ] if $cnt >= 3;
  }
  # Southern wall
  $scut = 1 if $scut == 0;
  foreach my $y ($self->height - $scut .. $self->height) {
    # Loop through the row. Keep a counter of how many consecutive wall tiles
    # occur with nothing above them. Store the first coordinate and the last
    # coordinate. When blank space or a floor tile is reached, add the wall if
    # it was long enough.
    my $cnt = 0;
    my $x1 = 0;
    my $x2 = 0;
    my $mode = 0; # One when we've got a wall
    foreach my $x (0 .. $self->width) {
      if ($self->{Map}[$y][$x]{_} eq "#") {
        next if $y != $self->height and $self->{Map}[$y + 1][$x]{_} ne " ";
        $x1 = $x if $mode == 0; # Is this our first tile?
        $mode = 1;  # Inevitably
        $x2 = $x;
        $cnt++;
      } else {
        if ($mode == 1) {
          # Woo! We might have a valid wall.
          push @{ $data->{S} }, [ $y, $x1, $y, $x2 ] if $cnt >= 3;
          # Clear things.
          $cnt = $mode = $x1 = $x2 = 0;
        } else {
          next;
        }
      }
    }
    # Now see if there's anything stored up that hasn't been processed.
    push @{ $data->{S} }, [ $y, $x1, $y, $x2 ] if $cnt >= 3;
  }
  # Western wall
  foreach my $x (0 .. $wcut) {
    # Loop through the row. Keep a counter of how many consecutive wall tiles
    # occur with nothing above them. Store the first coordinate and the last
    # coordinate. When blank space or a floor tile is reached, add the wall if
    # it was long enough.
    my $cnt = 0;
    my $y1 = 0;
    my $y2 = 0;
    my $mode = 0; # One when we've got a wall
    foreach my $y (0 .. $self->height) {
      if ($self->{Map}[$y][$x]{_} eq "#") {
        next if $x != 0 and $self->{Map}[$y][$x - 1]{_} ne " ";
        $y1 = $y if $mode == 0; # Is this our first tile?
        $mode = 1;  # Inevitably
        $y2 = $y;
        $cnt++;
      } else {
        if ($mode == 1) {
          # Woo! We might have a valid wall.
          push @{ $data->{W} }, [ $y1, $x, $y2, $x ] if $cnt >= 3;
          # Clear things.
          $cnt = $mode = $y1 = $y2 = 0;
        } else {
          next;
        }
      }
    }
    # Now see if there's anything stored up that hasn't been processed.
    push @{ $data->{W} }, [ $y1, $x, $y2, $x ] if $cnt >= 3;
  }
  # Eastern wall
  $ecut = 1 if $ecut == 0;
  foreach my $x ($self->width - $ecut .. $self->width) {
    # Loop through the row. Keep a counter of how many consecutive wall tiles
    # occur with nothing above them. Store the first coordinate and the last
    # coordinate. When blank space or a floor tile is reached, add the wall if
    # it was long enough.
    my $cnt = 0;
    my $y1 = 0;
    my $y2 = 0;
    my $mode = 0; # One when we've got a wall
    foreach my $y (0 .. $self->height) {
      if ($self->{Map}[$y][$x]{_} eq "#") {
        next if $x != $self->width and $self->{Map}[$y][$x + 1]{_} ne " ";
        $y1 = $y if $mode == 0; # Is this our first tile?
        $mode = 1;  # Inevitably
        $y2 = $y;
        $cnt++;
      } else {
        if ($mode == 1) {
          # Woo! We might have a valid wall.
          push @{ $data->{E} }, [ $y1, $x, $y2, $x ] if $cnt >= 3;
          # Clear things.
          $cnt = $mode = $y1 = $y2 = 0;
        } else {
          next;
        }
      }
    }
    # Now see if there's anything stored up that hasn't been processed.
    push @{ $data->{E} }, [ $y1, $x, $y2, $x ] if $cnt >= 3;
  }
  # Kludgy. Don't feel like going back and changing it though!
  foreach my $dir (qw(N S W E)) {
    foreach my $i (0 .. $#{ $data->{$dir} }) {
      $data->{$dir}[$i] = {
        Y1 => $data->{$dir}[$i][0],
        X1 => $data->{$dir}[$i][1],
        Y2 => $data->{$dir}[$i][2],
        X2 => $data->{$dir}[$i][3]
      };
    }
  }
  $data->{Type} = "Room";
  $self->{Exits} = $data;
  return 1;
}

42;
