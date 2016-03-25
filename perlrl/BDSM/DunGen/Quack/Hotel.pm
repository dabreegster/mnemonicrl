package BDSM::DunGen::Hotel;

use strict;
use warnings;
use Util;

use BDSM::Map;
use POSIX ("ceil");

sub generate {
  my $class = shift;

  # Load all the rooms we have.
  my %rooms;
  foreach (glob "content/hotel/*") {
    my $room = BDSM::Map->new($_);
    $rooms{ $room->{_Data}{Owner} } = $room;
  }

  # 8x15 by default
  my $map = BDSM::Map->new(18, 18 * ceil(scalar(keys(%rooms)) / 2), ".");
  $map->border;

  my $cnt = 0;
  foreach (sort keys %rooms) {
    my $room = $rooms{$_};
    my $Y = 10 * ($cnt % 2);
    my $X = 18 * int($cnt / 2);
    foreach my $y (0 .. $room->height) {
      foreach my $x (0 .. $room->width) {
        %{ $map->{Map}[$Y + $y][$X + $x] } = %{ $room->tile($y, $x) };
      }
    }
    $cnt++;
  }

  $map->fill([10, 0], [10, $map->width], "#");

  return $map;
}

42;
