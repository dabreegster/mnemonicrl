package BDSM::Map;

use strict;
use warnings;
use Util;

# They give us methods for modifying the map.
use BDSM::Map::Transform;
use BDSM::Map::Inspect;
use PUtil::Hook;
our @ISA = ("BDSM::Map::Transform", "BDSM::Map::Inspect", "PUtil::Hook");

use Game::Container;

use Data::Dumper;

GAME->{BDSMLayers} = {
  # Normal tile is technically 0; render will see this.
  symbol   => 1,
  bgstatic => 2,
  # Actor is technically 3; render will see this.
  fgstatic => 4,
  effect   => 5,
  snow     => 6,
  name     => 7,
  hilite   => 8
  # 9 is reserved for super override?
};

my %dontsend = map { $_ => 1 }
  ("_", "Layers", "Actor", "Inv", "Scent", "OnEnter", "OnExit", "Lit", "Stair");

# Create a new map of specififed dimensions and $blank tiles.
sub new {
  my ($class, $opts, @args) = args @_;
  my ($height, $width, $blank, $load);
  if (@args == 1) {
    $load = shift @args;
  } else {
    $height = shift @args;
    $width = shift @args;
    $blank = shift(@args) || " ";
  }

  my $self = ref $class ? $class : bless {
    Map        => [],
    Agents     => {},
    Rectangles => {},
    Toys       => {}
  }, $class;

  if ($load) {
    my $data;
    ($self->{Map}, $data) = _loadmap($load);
    @$self{keys %$data} = values %$data;  # Hash merge
    $self->{File} = $load;
    if ($load =~ s/map$/script/) {
      $self->loadscript($load) if -f $load;
    }
  } else {
    # Initialize the map with $blanks.
    foreach my $y (0 .. $height) {
      foreach my $x (0 .. $width) {
        $self->{Map}[$y][$x] = {
          _ => $blank
        };
      }
    }
  }
  my $data = $opts->{dat} // {};
  my $ourdat = $self->{_Data};  # TODO i hate hash merges.
  @$ourdat{keys %$data} = values %$data;  # Hash merge
  $self->{Depth} ||= $self->{_Data}{Depth} if $self->{_Data}{Depth};

  # Bring in the toys
  # When we make them, they'll repopulate the data list so dynamic ones are the same
  my $toyls = delete $self->{_Data}{Toys};
  foreach my $toy (@$toyls) {
    my $class = "BDSM::Toy::" . shift @$toy;
    my $cnt = 0;
    # Add in the flag style again
    $class->new($self, map { $cnt++ % 2 ? $_ : "-$_" } @$toy);
  }

  unless (GAME->{NoMapPostProc}) {
    $self->hotel_doors if $self->{_Data}{HotelDoors};
  }

  # Make staircases
  $self->{_Data}{MkStairs} //= [];
  $self->stair(@$_) foreach @{ $self->{_Data}{MkStairs} };

  return $self;
}

# Deepcopy a tile
sub copy {
  my ($map, $y, $x) = @_;
  my $tile = $map->tile($y, $x);
  # TODO bug?
  unless ($tile) {
    debug "$y, $x prolly out of bounds.";
    debug [caller];
    debug [caller(1)];
    debug [caller(2)];
    return {};
  }
  my $copy = { %$tile };
  $copy->{Layers} = [ map { [@$_] } @{ $tile->{Layers} } ];
  return $copy;
}

# Change a tile or add tile layer and perform callbacks.
sub mod {
  my ($self, $y, $x);
  $self = shift; $y = shift; $x = shift;
  my $copy = $self->copy($y, $x);
  if (@_ == 1) {
    my $tile;
    ($tile) = @_;
    if (ref $tile) {
      $self->{Map}[$y][$x]{Actor} = $tile;
    } else {
      $self->{Map}[$y][$x]{_} = $tile;
    }
  } elsif (@_) {
    my ($layer, @args) = @_;
    my $tile = $self->{Map}[$y][$x];
    $tile->{Layers} ||= [];
    $tile = $tile->{Layers};
    my $this = GAME->{BDSMLayers}{$layer};
    # Find this layer
    if (@$tile) {
      for (reverse(0 .. $#{ $tile }), -1) {
        if ($_ == -1) {
          # At the very bottom of the list, then
          unshift(@$tile, [$this, @args]);
          last;
        }
        next if $this < $tile->[$_][0];
        splice(@$tile, $_ + 1, 0, [$this, @args]);
        last;
      }
    } else {
      push @$tile, [$this, @args];
    }
  } else {
    debug ["mod with no args!", caller];
  }
  $self->modded($y, $x, $copy);
}

# Mod a tile's layer, but default to overwriting an existing layer
sub overmod {
  my ($self, $y, $x, $layer, @args) = @_;
  my $copy = { %{ $self->{Map}[$y][$x] } };
  $copy->{Layers} = [ map { [@$_] } @{ $self->{Map}[$y][$x]{Layers} } ];

  my $tile = $self->{Map}[$y][$x];
  $tile->{Layers} ||= [];
  $tile = $tile->{Layers};
  my $this = GAME->{BDSMLayers}{$layer};
  # Find this layer
  if (@$tile) {
    for (reverse(0 .. $#{ $tile }), -1) {
      if ($_ == -1) {
        # At the very bottom of the list, then
        unshift(@$tile, [$this, @args]);
        last;
      }
      next if $this < $tile->[$_][0];
      if ($this == $tile->[$_][0]) {
        @{ $tile->[$_] } = ($this, @args);
      } else {
        splice(@$tile, $_ + 1, 0, [$this, @args]);
      }
      last;
    }
  } else {
    push @$tile, [$this, @args];
  }
  $self->modded($y, $x, $copy);
}

# Delete a layer from a tile (top-most of that type)
sub del {
  my ($self, $y, $x, $layer, $constraint) = @_;
  my $tile = $self->{Map}[$y][$x]{Layers};
  for (reverse 0 .. $#{ $tile }) {
    next if GAME->{BDSMLayers}{$layer} != $tile->[$_][0];
    next if $constraint and $tile->[$_][ $constraint->[0] ] != $constraint->[1];
    splice(@$tile, $_, 1);
    last;
  }
  $self->modded($y, $x);
}

# Perform callbacks on a tile that has changed.
sub modded {
  my ($self, @info) = @_;
  # @info = ($y, $x) almost always and occasionally a third $copy of old
  $self->hookshot("mod", @info);
}

# Create a map from a file. New style with layers.
sub _loadmap {
  my $filename = shift;
  my @file;
  if (ref $filename) {
    # We may have gotten it from the network...
    @file = split(/\n/, $filename->[0]);
  } else {
    @file = slurp($filename);
  }

  shift @file;  # Layer 1
  my $map = [];
  while ($file[0] ne "LAYER2") {
    my $line = shift @file;
    my @row = map { { _ => $_ } } split(//, $line);
    push @$map, \@row;
  }

  my $symlayer = GAME->{BDSMLayers}{symbol};
  shift @file;  # Layer 2
  my $y = 0;
  while ($file[0] ne "LAYER3") {
    my $line = shift @file;
    my $x = 0;
    foreach (split(//, $line)) {
      $x++, next if $_ eq " ";
      $map->[$y][$x]{Layers}[0] = [$symlayer, $_];
      $x++;
    }
    $y++;
  }

  shift @file;  # Layer 3
  $y = 0;
  while ($file[0] ne "LAYER4") {
    my $line = shift @file;
    my $x = 0;
    foreach (split(/,/, $line)) {
      $x++, next unless $_;
      # This is how we realize there are blank spaces deliberately in LAYER2
      if ($map->[$y][$x]{Layers}[0]) {
        push @{ $map->[$y][$x]{Layers}[0] }, $_;
      } else {
        $map->[$y][$x]{Layers}[0] = [$symlayer, " ", $_];
      }
      $x++;
    }
    $y++;
  }

  # Layer 4 - Flags
  shift(@file);
  my $VAR1;
  eval join("\n", @file) or die "$filename data: $@\n";
  foreach my $flag (keys %$VAR1) {
    next if $flag eq "_Data";
    foreach my $value (keys %{ $VAR1->{$flag} }) {
      foreach my $tile (@{ $VAR1->{$flag}{$value} }) {
        $map->[ $tile->[0] ][ $tile->[1] ]{$flag} = $value;
      }
    }
  }

  return ($map, $VAR1);
}

# Save a map to a file
sub _savemap {
  my $map = shift;
  my @save;

  my $flags = {};

  # Layer 1
  push @save, "LAYER1";
  foreach my $y (0 .. $map->height) {
    my $line = "";
    foreach my $x (0 .. $map->width) {
      my $tile = $map->{Map}[$y][$x];
      $line .= $tile->{_};

      # Also work on some Layer 4 stuff here
      foreach my $key (keys %$tile) {
        next if $dontsend{$key};
        my $val = $key eq "Stair" ? $tile->{$key}[0] : $tile->{$key};
        $flags->{$key}{$val} ||= [];
        push @{ $flags->{$key}{$val} }, [$y, $x];
      }
    }
    push @save, $line;
  }

  # Layer 2
  push @save, "LAYER2";
  foreach my $y (0 .. $map->height) {
    my $line = "";
    foreach my $x (0 .. $map->width) {
      my $symbol = $map->toplayer($y, $x, "symbol");
      $line .= $symbol ? $symbol->[1] : " ";
    }
    push @save, $line;
  }

  # Layer 3
  # I gave up on encoding
  push @save, "LAYER3";
  foreach my $y (0 .. $map->height) {
    my $line = "";
    foreach my $x (0 .. $map->width) {
      my $symbol = $map->toplayer($y, $x, "symbol");
      $line .= $symbol ? "$symbol->[2]," : ",";
    }
    push @save, $line;
  }

  # Layer 4
  push @save, "LAYER4";
  push @save, "\$VAR1 = {";

  my @dump;
  # Handle the coordinate lists of doom
  foreach my $type (keys %$flags) {
    push @dump, "$type => {";
    foreach my $set (keys %{ $flags->{$type} }) {
      my @pp = ("  $set => [ ");
      my $pad = length($pp[0]);
      my @pts = map { "[" . join(", ", @$_) . "], " } @{ $flags->{$type}{$set} };
      foreach my $pt (@pts, " ],") {
        $pp[-1] =~ s/, $// if $pt eq " ],";
        if (length($pp[-1]) + length($pt) <= 90) {
          $pp[-1] .= $pt;
        } else {
          push @pp, (" " x $pad) . $pt;
        }
      }
      if (@pp > 1) {
        # Put the closing brace on its own line
        $pp[-1] =~ s/ ],$//;
        push @pp, (" " x ($pad - 2)) . "],";
      }
      push @dump, @pp;
    }
    $dump[-1] =~ s/,$//;
    push @dump, "}, ";
  }
  $dump[-1] =~ s/, $// if @dump;

  # And now the data... most of it
  $map->{_Data} //= {};
  my $dat = { %{ $map->{_Data} } };
  delete $dat->{MkStairs};
  $dat->{Stairs} //= [];
  $dat->{Toys} //= [];
  my @stairs = map {
    my @x = @$_; [map { /^\d+$/ ? $_ : "\"$_\"" } @x]
  } @{ delete $dat->{Stairs} };
  my @toys = @{ delete $dat->{Toys} };

  # Nicer to edit, please.
  $Data::Dumper::Indent = 1;
  $Data::Dumper::Quotekeys = 0;
  my @data = split(/\n/, Data::Dumper::Dumper($dat));
  shift @data;

  $Data::Dumper::Indent = 2;
  $Data::Dumper::Quotekeys = 1;

  # Manually do arrays... Data::Dumper insists on sucking
  pop(@data);
  $data[-1] .= "," if @data;

  push @data, "  Toys => [";
  foreach (@toys) {
    my $line = Data::Dumper::Dumper($_);
    $line =~ s/^\$VAR1 = //;
    $line =~ s/\n/ /g;
    $line =~ s/\s+/ /g;
    $line =~ s/;/,/;
    push @data, "    $line";
  }
  push @data, "  ],";

  push @data, "  MkStairs => [";
  push @data, "    [" . join(", ", @$_) . "]," foreach @stairs;
  push @data, "  ]";

  $dump[-1] .= "," if @dump;
  push @dump, "_Data => {";
  push @dump, @data;
  push @dump, "}";

  push @save, map { "  $_" } @dump;
  push @save, "};";

  return join "\n", @save;
}

# Top-most, please
sub toplayer {
  my ($map, $y, $x, $layer, $tile);
  if (@_ == 4) {
    ($map, $y, $x, $layer) = @_;
    $tile = $map->{Map}[$y][$x]{Layers};
  } elsif (@_ == 3) {
    ($map, $tile, $layer) = @_;
    $tile = $tile->{Layers};
  }
  my $this = GAME->{BDSMLayers}{$layer};
  for (reverse 0 .. $#{ $tile }) {
    return $tile->[$_] if $this == $tile->[$_][0];
  }
  return;
}

# Flyweight containers since we don't want to waste creating one on every tile of a giant
# map.
sub inv {
  my ($self, $y, $x, $cmd, @args) = @_;
  my $tile = $self->tile($y, $x);

  # If the tile has a Container, delegate.
  if ($tile->{Inv}) {
    my @code = $tile->{Inv}->$cmd(@args);
    $self->modded($y, $x);  # Re-render if necessary
    return @code;
  }

  # Handle Container's methods ourselves, sort of.
  return undef if $cmd eq "get";
  return () if $cmd eq "all";
  die "cant delete item off tile w/o a container!" if $cmd eq "del";

  # Actually create a Container.
  $tile->{Inv} = Game::Container->new($tile);
  $tile->{Inv}->$cmd(@args);
  $self->modded($y, $x);  # Re-render if necessary
}

# Pack ourselves up to send through network.
sub serialize {
  my $map = shift;

  my $send = {
    Depth => $map->{Depth},
    Agents => [],
    MapItems => [],
    Global   => GAME->{Global}
  };
  if ($map->{File}) {
    $send->{File} = $map->{File};
    $send->{State} = $map->{_Data};
  } else {
    $send->{Map} = $map->_savemap;
  }
  my %already_saved;  # We will encounter "multiple" sprites; don't re-send them
  foreach my $y (0 .. $map->height) {
    foreach my $x (0 .. $map->width) {
      my $tile = $map->{Map}[$y][$x];
      # If the tile has agents or items, send those too -- they're gonna be relevant.
      if ($tile->{Actor} and !$already_saved{ $tile->{Actor}{Aggregate}{ID} }) {
        $already_saved{ $tile->{Actor}{Aggregate}{ID} } = 1;
        push @{ $send->{Agents} }, $tile->{Actor}{Aggregate}->serialize;
      }
      if ($tile->{Inv}) {
        push @{ $send->{MapItems} }, map { [$_->serialize, $y, $x] } $tile->{Inv}->all;
      }
    }
  }

  bless $send, ref($map);   # So we can get at the unserialize routine later.
  return $send;
}

# Recreate ourselves on the other end of the network.
sub unserialize {
  my $self = shift;
  my $map = $self->{File} ?
    BDSM::Map->new(-dat => $self->{State}, $self->{File}) :
    BDSM::Map->new([$self->{Map}]);
  $map->{Depth} = $self->{Depth};

  return $map;
}

# Execute a map's script
sub script {
  my ($map, $script, @args) = @_;
  my $sub = eval $map->{Scripts}{$script};
  debug($@), die unless $sub;
  $sub->($map, @args);
}

# Multiple ones can be in a file
sub loadscript {
  my ($map, $file) = @_;
  my @lines = slurp($file);
  shift @lines;   # Shebang line so vim highlights the code

  while (@lines) {
    my $name = shift @lines;
    $name =~ m/^___SCRIPT (\w+)___$/;
    $name = $1;
    my $eval = "sub {\n";
    until (@lines == 0 or $lines[0] =~ m/^___/) {
      $eval .= shift(@lines) . "\n";
    }
    $map->{Scripts}{$name} = "$eval\n}";
  }
}

# Maintain a list of agents
sub join {
  my ($self, $agent) = @_;
  $self->{Agents}{ $agent->{ID} } = $agent;
  if (GAME->fullsim) {
    $agent->{HP}->start if $agent->{HP};
    $agent->{ESM}->start if $agent->{ESM};
  }
}

sub quit {
  my ($self, $agent) = @_;
  delete $self->{Agents}{ $agent->{ID} };
  return unless GAME->fullsim;
  GAME->unschedule(-tags => ["stat_$agent->{ID}"]);
}

42;
