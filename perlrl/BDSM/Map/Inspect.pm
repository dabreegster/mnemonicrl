package BDSM::Map::Inspect;

use strict;
use warnings;
use Util;

use Heap::Priority;
use BDSM::Vector;
# We simply extend BDSM::Map with more methods. We provide info about the map.

# Verify coordinates are within bounds.
sub check {
  my ($self, $y, $x) = @_;
  if ($y < 0 or $y > $self->height or $x < 0 or $x > $self->width) {
    debug "out of bounds coords $y, $x...";
    return;
  }
  return 1;
}

# Verify coordinates are within bounds, but silently. They're expecting it to fail.
sub stfucheck {
  my ($self, $y, $x) = @_;
  return if $y < 0 or $y > $self->height or $x < 0 or $x > $self->width;
  return 1;
}

# Return the specified tile. (Full data structure)
sub tile {
  my ($self, $y, $x) = @_;
  return $self->{Map}[$y][$x];
}

# Return the specified tile's residing actor or simple type.
sub get {
  my ($self, $y, $x, $layer) = @_;
  # stfucheck?
  return "" unless $self->check($y, $x);  # So we can do tests w/o unitialized values
  my $tile = $self->{Map}[$y][$x];
  if ($layer) {
    return $self->toplayer($y, $x, $layer);
  } else {
    return $tile->{Actor} ? $tile->{Actor} : $tile->{_};
  }
}

# QUIETLY Return the specified tile's residing actor or simple type.
sub _get {
  my ($self, $y, $x, $layer) = @_;
  return "" unless $self->stfucheck($y, $x);  # So we can do tests w/o unitialized values
  my $tile = $self->{Map}[$y][$x];
  if ($layer) {
    return $self->toplayer($y, $x, $layer);
  } else {
    return $tile->{Actor} ? $tile->{Actor} : $tile->{_};
  }
}

# Quietly get a tile's feature
sub feature {
  my ($self, $y, $x) = @_;
  return "" unless $self->stfucheck($y, $x);
  return $self->tile($y, $x)->{Feature} // "";
}

# Calculate map height.
sub height {
  my $self = shift;
	return $#{ $self->{Map} };
}

# Calculate map width.
sub width {
  my $self = shift;
  # All maps are rectangular; thus, each row is the same width.
	return $#{ $self->{Map}[0] };
}

# Quick and simple dump to STDERR in a format suitable for viewing with most(1)
sub _dump {
  my ($self, $args, $fh, $y1, $x1, $y2, $x2) = args @_;
  $fh //= *STDERR;
  unless (defined($y1)) {
    ($y1, $x1, $y2, $x2) = (0, 0, $self->height, $self->width);
  }
  foreach my $y ($y1 .. $y2) {
    my $line;
    foreach my $x ($x1 .. $x2) {
      my $tile = $self->{Map}[$y][$x];
      if ($args->{syms}) {
        my $top = $self->toplayer($y, $x, "symbol");
        $line .= $top ? $top->[1] : $tile->{_};
      } else {
        $line .= $tile->{_};
      }
    }
    print $fh "$line\n";
  }
}

# Finds a random tile on the map.
# Not a spawnpt chooser anymore by default.
sub getpt {
  my ($self, $opts, $y1, $x1, $y2, $x2) = args @_;
  ($y1, $x1, $y2, $x2) = (0, 0, $self->height, $self->width) unless defined $y1;
  $y1 = 0 if $y1 < 0;
  $x1 = 0 if $x1 < 0;
  $y2 = $self->height if $y2 > $self->height;
  $x2 = $self->width if $x2 > $self->width;
  my ($y, $x);
  my $match = $opts->{match} // ".";
  while (1) {
    $y = random($y1, $y2);
    $x = random($x1, $x2);
    next if ref $self->get($y, $x);
    #next unless $self->permeable($y, $x);
    next unless $self->get($y, $x) eq $match;  # If we want ' ', then mark a spawnpt?
    # TODO: nah, put spawnable in the tilemap so we can use profiles?
    last;
  }
  return ($y, $x);
}

# A*s a path from one point to another.
sub pathfind {
  my ($map, $diag, $y1, $x1, $y2, $x2) = @_;

  # Save some time.
  return if $y1 == $x1 and $y2 == $x2;
  return unless $map->get($y2, $x2) =~ m/^(\.| )$/;

  # Set up the priority heap for A*
  my $open = Heap::Priority->new;
  $open->lowest_first;

  # Make a temp copy of the blockmap
  my $virtmap = [];
  # TODO: dont think we need to do this; autovivify!
  #foreach my $y (0 .. $map->height) {
  #  foreach my $x (0 .. $map->width) {
  #    $virtmap->[$y][$x] = {};
  #  }
  #}
  $open->add({ Y => $y1, X => $x1, P => 0 }, 0);
  $virtmap->[$y1][$x1]{Used} = 1;

  while (my $node = $open->pop) {
    # Success?
    if ($node->{Y} == $y2 and $node->{X} == $x2) {
      my ($y, $x) = ($node->{Y}, $node->{X});
      my @path = ([$y, $x]);
      while (my $backref = $virtmap->[$y][$x]{Backref}) {
        ($y, $x) = @$backref;
        unshift @path, [$y, $x];
      }
      shift @path;  # We already know about ($y1, $x1).
      return @path;
    }

    foreach (adjacent_tiles($diag, $node->{Y}, $node->{X})) {
      my ($y, $x) = @$_;
      next if $virtmap->[$y][$x]{Used};
      next unless $map->get($y, $x) =~ m/^(\.| )$/;

      my $h = abs($y - $y2) + abs($x - $x2) + $node->{P};
      $virtmap->[$y][$x]{Used} = 1;
      $virtmap->[$y][$x]{Backref} = [$node->{Y}, $node->{X}];
      $open->add({ Y => $y, X => $x, P => $h }, $h);
    }
  }
  return;
}

# Locate the best adjacent tile satisfying given constraints.
sub bestadj {
  my ($map, %opts) = @_;
  my $diag = $opts{diag} ? "diag" : "orthog";

  my @best;
  foreach (adjacent_tiles($diag, @{ $opts{from} })) {
    my ($y, $x) = @$_;
    my $tile = $map->{Map}[$y][$x];
    next unless $map->permeable($tile);
    next if $tile->{Actor} and !$opts{actors};
    my $score = $opts{score}->($y, $x);
    next unless defined($score);
    if ($opts{rank} eq "lowest") {
      @best = ($score, $y, $x) if $#best == -1 or $score < $best[0];
    } else {
      @best = ($score, $y, $x) if $#best == -1 or $score > $best[0];
    }
  }
  return @best ? ($best[1], $best[2]) : ();
}

# Cast FOV-like scent around and activate sleeping monsters too
sub logicfov {
  my ($map, $agent) = @_;

  my $r = 5;  # TODO: lol
  my $maxr = $r * sqrt(2);

  # It's stupid to do proper shadowcasting here too; monsters wake up by proximity. Call it
  # scent, gut feeling, whatever.
  # Hell, call it laziness.
  
  foreach my $y ($agent->{Y} - $r .. $agent->{Y} + $r) {
    foreach my $x ($agent->{X} - $r .. $agent->{X} + $r) {
      next unless $map->stfucheck($y, $x);
      my $tile = $map->{Map}[$y][$x];
      $tile->{Scent}{ $agent->{ID} } 
        = ($agent->{TurnCntr} * $maxr) - euclid($y, $x, $agent->{Y}, $agent->{X});

      if (my $baddy = $tile->{Actor}) {
        # Don't activate sprites or ourselves, only monsters
        next unless defined($baddy->{ID}) and $baddy->{ID} != $agent->{ID};
        next unless $baddy->is("Monster");
        $agent->{Journal}{ $baddy->type } = 1;

        $baddy->fxn("WhenDisturbed", $agent);
      }
    }
  }
}

sub permeable {
  my $map = shift;
  my $tile = @_ == 2 ? $map->tile(@_) : shift;
  if (ref $tile eq "HASH" and !$tile->{_}) {
    debug "wonky permeable tile", $tile;
  }
  $tile = $tile->{_} if ref $tile eq "HASH";
  return CFG->{Tilemap}{$tile}{Permeable};
}

sub seethru {
  my $map = shift;
  my $tile = @_ == 2 ? $map->tile(@_) : shift;
  $tile = $tile->{_} if ref $tile eq "HASH";
  return CFG->{Tilemap}{$tile}{Transparent};
}

# Bresenham line algo
sub line {
  # TODO: return empty if out of range and flipped coords
  my ($map, $y1, $x1, $y2, $x2, $range) = @_;
  return if $y1 == $y2 and $x1 == $x2;
  my @pts;
  my @orig = ($y1, $x1);
  my $steep = abs($y1 - $y2) > abs($x1 - $x2);                         
  if ($steep) {
    ($x1, $y1) = ($y1, $x1);
    ($x2, $y2) = ($y2, $x2);
  }
  my $reverse;
  if ($x1 > $x2) {
    ($x1, $x2) = ($x2, $x1);
    ($y1, $y2) = ($y2, $y1);
    $reverse = 1;
  }
  my $dx = $x2 - $x1;
  my $dy = abs($y2 - $y1);
  my $err = 0;
  my $derr = $dy / $dx;
  my $ystep = $y1 < $y2 ? 1 : -1;
  my $y = $y1;
  for my $x ($x1 .. $x2) {
    my @coords = $steep ? ($x, $y) : ($y, $x);
    unless ($coords[0] == $orig[0] and $coords[1] == $orig[1]) {
      last if $range and euclid(@coords, @orig) >= $range;
      push @pts, \@coords;
      if (!$map->permeable(@coords)) {
        $reverse ? @pts = () : last;
      }
    }
    $err += $derr;
    next unless $err >= 0.5;
    $y += $ystep;
    $err -= 1;
  }
  @pts = reverse @pts if $reverse;
  return @pts;
}

# Choose a random spawn point
sub spawnpt {
  my ($map, $group) = @_;
  # TODO: wont handle spawning stuff on top of stuff. like, item can go where actor is?
  $group ||= "main";
  my ($y, $x);
  do {
    ($y, $x) = $map->{spawnpt} ?
      @{ choosernd(@{ $map->{spawnpt}{$group} }) } : $map->getpt;
  } while $map->tile($y, $x)->{Actor};
  return ($y, $x);
}

# Find the nearest tile matching a condition AND return a path to it!
sub floodfind {
  my ($map, $y1, $x1, $key, $match) = @_;

  my @open;

  # Make a temp copy of the map
  my $virtmap = [];
  foreach my $y (0 .. $map->height) {
    foreach my $x (0 .. $map->width) {
      $virtmap->[$y][$x] = {};
    }
  }
  push @open, [$y1, $x1];
  $virtmap->[$y1][$x1]{Used} = 1;

  while (my $next = shift @open) {
    my $node = $map->{Map}[ $next->[0] ][ $next->[1] ];
    # Success?
    if (exists $node->{$key} and $node->{$key} eq $match) {
      my ($y, $x) = (@$next);
      my @path = ([$y, $x]);
      while (my $backref = $virtmap->[$y][$x]{Backref}) {
        ($y, $x) = @$backref;
        unshift @path, [$y, $x];
      }
      shift @path;  # We already know about ($y1, $x1).
      return @path;
    }

    foreach (adjacent_tiles("diag", @$next)) {
      my ($y, $x) = @$_;
      next if $virtmap->[$y][$x]{Used};
      next unless $map->get($y, $x) =~ m/^(\.| )$/;

      $virtmap->[$y][$x]{Used} = 1;
      $virtmap->[$y][$x]{Backref} = [@$next];
      push @open, [$y, $x];
    }
  }
  return;
}

# Are we a special level or part of a dungeon?
sub normal {
  my $map = shift;
  return $map->{Depth} =~ m/^\d+$/;
}

# Does bounds checking.
sub adj_tiles {
  my $map = shift;
  return grep { $map->stfucheck(@$_) } adjacent_tiles(@_);
}

# Diffuse a scent gradient through the permeable portions of the map and tag it. Optimal
# for initialization-time calls... it makes run-time pathfinding super cheap.
sub influence_map {
  my ($map, $tag, $y1, $x1) = @_;
  debug "Diffusing scent for $tag over $map->{Depth} from $y1, $x1...";
  $map->tile($y1, $x1)->{Scents}{$tag} = 1;
  my @ls = ([$y1, $x1]);
  my $max = 0;
  while (my $cur = shift @ls) {
    my $scent = $map->tile(@$cur)->{Scents}{$tag} + 1;
    $max = $scent if $scent > $max;
    # one of the most vital lessons about diffusion... dont do diag. winds up replicating,
    # so you get a pocket of '15' in a corner. Very bad, causes local minima like hell.

    # Erm, we're only good for climbing down. Can't really use for pacing.

    foreach my $adj ($map->adj_tiles("orthog", @$cur)) {
      next unless $map->permeable(@$adj);
      next if $map->tile(@$adj)->{Scents}{$tag};
      $map->tile(@$adj)->{Scents}{$tag} = $scent;
      push @ls, $adj;
    }
  }
  $map->{MaxScent}{$tag} = $max;
}

42;
