########
# Area #
########

package Roguelike::Area;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::Tilemap;
use Roguelike::Container;

use Exporter ();
our @ISA = ("Exporter");
our @EXPORT = do {
  no strict "refs";
  grep defined &$_, keys %{ __PACKAGE__ . "::" };
};

sub loadmap {
  # We only handle very simple maps with no data. For now.
  my $file = shift;
  die "Couldn't open map $file: $1\n" unless open(MAP, $file);
  my $map = [];
  foreach my $row (<MAP>) {
    $row =~ s/\n//;
    my @line = ();
    foreach my $tile (split(//, $row)) {
      push @line, {
        _    => $tile,
        Char => undef
      };
    }
    push @{ $map }, \@line;
  }
  close(MAP);
  my $self = new Roguelike::Tilemap $map;
  foreach my $y (0 .. $self->height) {
    foreach my $x (0 .. $self->width) {
      $self->{Map}[$y][$x]{Inv} = new Roguelike::Container 0, $self->{Map}[$y][$x];
    }
  }
  $self->refresh;
  return $self;
}

sub place {
  my $figure = shift;
  my %data = @_;
  my $map = $data{on};
  my $Y = $data{at}->[0];
  my $X = $data{at}->[1];
  my $dir = $data{dir};
  my $banadj = $data{noadj};
  return if $figure->height + $Y > $map->height;
  return if $figure->width + $X > $map->width;
  # Pass 1 is checking.
  foreach my $y (0 .. $figure->height) {
    foreach my $x (0 .. $figure->width) {
      return unless $map->{Map}[$Y + $y][$X + $x]{_} eq " ";
      if ($banadj) {
        return if $map->{Map}[$Y + $y - 1][$X + $x]{_} eq "#";
        return if $map->{Map}[$Y + $y + 1][$X + $x]{_} eq "#";
        return if $map->{Map}[$Y + $y][$X + $x - 1]{_} eq "#";
        return if $map->{Map}[$Y + $y][$X + $x + 1]{_} eq "#";
        return if $map->{Map}[$Y + $y - 1][$X + $x - 1]{_} eq "#";
        return if $map->{Map}[$Y + $y - 1][$X + $x + 1]{_} eq "#";
        return if $map->{Map}[$Y + $y + 1][$X + $x - 1]{_} eq "#";
        return if $map->{Map}[$Y + $y + 1][$X + $x + 1]{_} eq "#";
      }
    }
  }
  # Pass 1 is putting the data there.
  foreach my $y (0 .. $figure->height) {
    foreach my $x (0 .. $figure->width) {
      $map->{Map}[$Y + $y][$X + $x] = $figure->{Map}[$y][$x];
      $map->{Map}[$Y + $y][$X + $x]{ID} = $#{$map->{Exits}} + 1;
    }
  }
  # Translate data too
  foreach
  (
    @{$figure->{Exits}{N}}, @{$figure->{Exits}{S}},
    @{$figure->{Exits}{E}}, @{$figure->{Exits}{W}}
  ) {
    $_->{Y1} += $Y;
    $_->{X1} += $X;
    $_->{Y2} += $Y;
    $_->{X2} += $X;
  }
  # Hotspots!
  foreach (@{ $figure->{Exits}{Hotspots} }) {
    $_->[0] += $Y;
    $_->[1] += $X;
  }
  push(@{$map->{Exits}}, $figure->{Exits});
  return 1;
}

sub connect {
  my $new = shift;
  my %data = @_;
  my $map = $data{on};
  my $dir = $data{dir};
  my $data = $map->{Exits}[ $data{to} ]{$dir}[ $data{wall} ];
  my $alignment = $data{aligned} || "";
  my ($y, $x, $skip);
  my $newwall = random(0, $#{ $new->{Exits}{opposite($dir)} });
  my $newdata = $new->{Exits}{opposite($dir)}[$newwall];
  if ($dir eq "N") {
    $y = $data->{Y1} - $newdata->{Y1} - 1;
    $x = $data->{X1} - $newdata->{X1};
    $skip = ($data->{X2} - $data->{X1}) - ($newdata->{X2} - $newdata->{X1});
    $x += random($skip) if $alignment eq "middle";
    $x += $skip if $alignment eq "end";
  } elsif ($dir eq "S") {
    $y = $data->{Y1} + 1 - $newdata->{Y1};
    $x = $data->{X1} - $newdata->{X1};
    $skip = ($data->{X2} - $data->{X1}) - ($newdata->{X2} - $newdata->{X1});
    $x += random($skip) if $alignment eq "middle";
    $x += $skip if $alignment eq "end";
  } elsif ($dir eq "E") {
    $y = $data->{Y1} - $newdata->{Y1};
    $x = $data->{X1} + 1 - $newdata->{X1};
    $skip = ($data->{Y2} - $data->{Y1}) - ($newdata->{Y2} - $newdata->{Y1});
    $y += random($skip) if $alignment eq "middle";
    $y += $skip if $alignment eq "end";
  } elsif ($dir eq "W") {
    $y = $data->{Y1} - $newdata->{Y1};
    $x = $data->{X1} - $newdata->{X1} - 1;
    $skip = ($data->{Y2} - $data->{Y1}) - ($newdata->{Y2} - $newdata->{Y1});
    my $foo = random($skip);
    $y += $foo if $alignment eq "middle";
    $y += $skip if $alignment eq "end";
  }
  return unless place($new, on => $map, at => [ $y, $x ], dir => $dir);
  $newdata = $map->{Exits}[-1]{opposite($dir)}[$newwall];
  if ($dir eq "N") {
    if ($newdata->{X2} - $newdata->{X1} < $data->{X2} - $data->{X1}) {
      $map->fill
      (
        [$newdata->{Y1},     $newdata->{X1} + 1],
        [$newdata->{Y1} + 1, $newdata->{X2} - 1],
        "."
      );
    } else {
      $map->fill
      (
        [$data->{Y1} - 1, $data->{X1} + 1],
        [$data->{Y1},     $data->{X2} - 1],
        "."
      );
    }
  } elsif ($dir eq "S") {
    if ($newdata->{X2} - $newdata->{X1} < $data->{X2} - $data->{X1}) {
      $map->fill
      (
        [$newdata->{Y1} - 1, $newdata->{X1} + 1],
        [$newdata->{Y1},     $newdata->{X2} - 1],
        "."
      );
    } else {
      $map->fill
      (
        [$data->{Y1},     $data->{X1} + 1],
        [$data->{Y1} + 1, $data->{X2} - 1],
        "."
      );
    }
  } elsif ($dir eq "W") {
    if ($newdata->{Y2} - $newdata->{Y1} < $data->{Y2} - $data->{Y1}) {
      $map->fill
      (
        [$newdata->{Y1} + 1, $newdata->{X1}],
        [$newdata->{Y2} - 1, $newdata->{X1} + 1],
        "."
      );
    } else {
      $map->fill
      (
        [$data->{Y1} + 1, $data->{X1} - 1],
        [$data->{Y2} - 1, $data->{X1}],
        "."
      );
    }
  } elsif ($dir eq "E") {
    if ($newdata->{Y2} - $newdata->{Y1} < $data->{Y2} - $data->{Y1}) {
      $map->fill
      (
        [$newdata->{Y1} + 1, $newdata->{X1} - 1],
        [$newdata->{Y2} - 1, $newdata->{X1}],
        "."
      );
    } else {
      $map->fill
      (
        [$data->{Y1} + 1, $data->{X1}],
        [$data->{Y2} - 1, $data->{X1} + 1],
        "."
      );
    }
  }
  $map->{Exits}[$data{to}]{$dir}[$data{wall}]{Exit} = $#{$map->{Exits}};
  $map->{Exits}[-1]{opposite($dir)}[$newwall]{Exit} = $data{to};
  return 1;
}

sub cellular {
  my $map = shift;
  my $iterations = shift || 15;
  my $old = [];
  foreach (1 .. $iterations) {
    # Invertion is EVIL
    foreach (1 .. 2) {
      # Store old copy!
      foreach my $y (0 .. $map->height) {
        foreach my $x (0 .. $map->width) {
          $old->[$y][$x] = $map->{Map}[$y][$x]{_};
        }
      }
      # Apply Game of Life rules
      foreach my $y (1 .. $map->height - 1) {
        foreach my $x (1 .. $map->width - 1) {
          # How many neighbors?
          my $neighbors = 0;
          $neighbors++ if $old->[$y - 1][$x - 1] eq "#";
          $neighbors++ if $old->[$y - 1][$x] eq "#";
          $neighbors++ if $old->[$y - 1][$x + 1] eq "#";
          $neighbors++ if $old->[$y][$x - 1] eq "#";
          $neighbors++ if $old->[$y][$x + 1] eq "#";
          $neighbors++ if $old->[$y + 1][$x - 1] eq "#";
          $neighbors++ if $old->[$y + 1][$x] eq "#";
          $neighbors++ if $old->[$y + 1][$x + 1] eq "#";
          #my $tile = $map->{Map}[$y][$x]{_};
          #if ($tile eq "#" and $neighbors < 2) {
          #  $tile = ".";
          #} elsif ($tile eq "#" and $neighbors > 3) {
          #  $tile = ".";
          #} elsif ($tile eq "." and $neighbors == 3) {
          #  $tile = "#";
          #}
          $map->{Map}[$y][$x]{_} = $neighbors < 3 ? "#" : ".";
        }
      }
    }
  }
  return 1;
}

sub transform {
  my $map = shift;
  my $from = shift;
  my $to = shift;
  foreach my $y (1 .. $map->height - 1) {
    foreach my $x (1 .. $map->width - 1) {
      $map->{Map}[$y][$x]{_} = $to if $map->{Map}[$y][$x]{_} eq $from;
    }
  }
  return 1;
}

sub populate {
  my $map = shift;
  #my $percent = shift;   # Don't need this
  # Assemble all hotspots
  my $hotspots = [];
  push @$hotspots, map { $_ } @{ $_->{Hotspots} } foreach @{ $map->{Exits} };
  # For now, every level has between 2 and 4 staircases both up and down,
  # spread out.
  # First up
  foreach (1 .. random(2, 4)) {
    my $dat = delrand($hotspots);
    $map->{Map}[ $dat->[0] ][ $dat->[1] ]{_} = "<";
    render($map->{Map}[ $dat->[0] ][ $dat->[1] ]);
    push @{ $map->{StairsUp} }, $dat;
  }
  # Then down
  foreach (1 .. random(2, 4)) {
    my $dat = delrand($hotspots);
    $map->{Map}[ $dat->[0] ][ $dat->[1] ]{_} = ">";
    render($map->{Map}[ $dat->[0] ][ $dat->[1] ]);
    push @{ $map->{StairsDown} }, $dat;
  }

  # Assemble lists using rarity.
  my $depth = int((100 * $map->{Depth}) / $Game->{MaxDepth});
  my (@common_items, @rare_items);
  foreach (@{ $Game->{ItemPopulation} }) {
    push @common_items, $_ if $_->g("Rank") == 2;
    if ($depth > 60) {
      push @rare_items, $_ if $_->g("Rank") == 1;
      push @common_items, $_ if $_->g("Rank") == 1 and $depth > 90;
    }
  }
  my (@common_monsters, @rare_monsters);
  foreach (@{ $Game->{MonsterPopulation} }) {
    push @common_monsters, $_ if $_->g("Rank") == 3;
    push @common_monsters, $_ if $_->g("Rank") == 2 and $depth > 40;
    push @common_monsters, $_ if $_->g("Rank") == 1 and $depth > 80;
    push @rare_monsters, $_ if $_->g("Rank") == 2 and $depth > 30 and $depth <= 90;
    push @rare_monsters, $_ if $_->g("Rank") == 1 and $depth > 90;
  }
  # Generate common items.
  foreach (1 .. random(8, 13)) {
    my $dat = delrand($hotspots);
    my $item = chooserand(@common_items)->new;
    if ($item->g("Wieldable") or $item->g("Wearable")) {
      if ($depth <= 30) {
        $item->{Mod} = min(3, 0, $item->g("MaxMod"));
      } elsif ($depth <= 60) {
        $item->{Mod} = min(2, 0, $item->g("MaxMod"));
      } elsif ($depth <= 90) {
        $item->{Mod} = random(0, $item->g("MaxMod"));
      } else {
        $item->{Mod} = max(2, 0, $item->g("MaxMod"));
      }
    }
    $map->{Map}[ $dat->[0] ][ $dat->[1] ]{Inv}->add($item);
    render($map->{Map}[ $dat->[0] ][ $dat->[1] ]);
  }
  # Generate common monsters.
  foreach (1 .. random(10, 20)) {
    my $dat = delrand($hotspots);
    chooserand(@common_monsters)->new(
      Z => $map->{Depth},
      Y => $dat->[0],
      X => $dat->[1]
    );
  }
  my $rare = 0;
  $rare = 1 if $depth > 30;
  $rare = 2 if $depth > 60;
  # Generate rare items.
  foreach (1 .. $rare) {
    last unless @rare_items;
    next unless $depth > 90 or percent($depth);
    my $dat = delrand($hotspots);
    my $item = chooserand(@rare_items)->new;
    if ($item->g("Wieldable") or $item->g("Wearable")) {
      if ($depth <= 30) {
        $item->{Mod} = min(3, 0, $item->g("MaxMod"));
      } elsif ($depth <= 60) {
        $item->{Mod} = min(2, 0, $item->g("MaxMod"));
      } elsif ($depth <= 90) {
        $item->{Mod} = random(0, $item->g("MaxMod"));
      } else {
        $item->{Mod} = max(2, 0, $item->g("MaxMod"));
      }
    }
    $map->{Map}[ $dat->[0] ][ $dat->[1] ]{Inv}->add($item);
    render($map->{Map}[ $dat->[0] ][ $dat->[1] ]);
  }
  # Generate rare monsters.
  foreach (1 .. $rare) {
    last unless @rare_monsters;
    next unless $depth > 90 or percent($depth);
    my $dat = delrand($hotspots);
    chooserand(@rare_monsters)->new(
      Z => $map->{Depth},
      Y => $dat->[0],
      X => $dat->[1]
    );
  }
  return 1;
}

42;
