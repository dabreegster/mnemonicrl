package BDSM::DunGen::GuestRoom;

use strict;
use warnings;
use Util;

use BDSM::Toy::Conveyor;

my %furniture;
# TODO see, this is why we need a resource manager
if (-f "content") { # why does this feel mildly wiseass
$furniture{$_} = BDSM::DunGen::Shape->new("content/hotel/furniture/$_.map") foreach
  (qw(armchair armoire bed curtains desk_lamp1 desk_lamp2 dresser floor_lamp mousehole));
}

sub generate {
  my ($class) = @_;

  my $map = BDSM::Map->new(20, 80, " ");
  my $floor = 11; # how far down
  $map->fill([$floor, 0], [$floor, 60], symbol => "_", "grey");

  my @ls = ("bed"); # Every room needs one
  push @ls, choosernd("desk_lamp1", "desk_lamp2", "floor_lamp");
  push @ls, choosernd("armoire", "dresser");
  push @ls, "mousehole" if percent(50);
  push @ls, "curtains" if percent(75);
  push @ls, "armchair" if percent(50);

  my $x = 0;
  foreach (shuffle(@ls)) {
    my $obj = $furniture{$_};
    debug "$_ failed?" unless $obj->place(on => $map, at => [$floor - $obj->height, $x], forceblit => 1);
    $x += $obj->width + 2;
  }
  #$map->_dump(-syms => 1); die;

  $map->{_Data}{$_} = 1 for qw(empty superlight nostairs);
  return $map;
}

42;
