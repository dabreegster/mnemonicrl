package PerlRL::Component::View::Effects;

use strict;
use warnings;
use Util;

use BDSM::Toy::Conveyor;

# TODO better organization, i dont like injecting all this shit into HexedUI

# Prerender for a great optimization!
#$ui->{_Prerender}{"Snow*"} = ord("*") | $ui->paint("white");
#$ui->{_Prerender}{"Snow."} = ord(".") | $ui->paint("white");
#$ui->{_Prerender}{"fire("} = ord("(") | $ui->paint("Red");
#$ui->{_Prerender}{"fire)"} = ord(")") | $ui->paint("Red");
#$ui->{_Prerender}{"smokeO"} = ord("O") | $ui->paint("grey");
#$ui->{_Prerender}{"smokeo"} = ord("o") | $ui->paint("grey");
#$ui->{_Prerender}{"greenfire("} = ord("(") | $ui->paint("Green");
#$ui->{_Prerender}{"greenfire)"} = ord(")") | $ui->paint("Green");

# Start an effect. Added to HexedUI :P
sub HexedUI::Interface::eyecandy {
  my ($ui, $effect) = @_;
  if ($effect eq "snow") {
    $ui->{_Effects}{Flakes} = [{ Flakes => [] }, { Flakes => [] }];
    GAME->schedule(
      -do   => [$ui, "_snowspawn"],
      -id   => "spawnsnow",
      -tags => ["map", "ui", "snow"]
    );
    GAME->schedule(
      -do   => [$ui, "_snow"],
      -id   => "snow$_",
      -tags => ["map", "ui", "snow"],
      -args => [$_]
    ) for 0 .. 1;
  } elsif ($effect eq "eye") {
    $ui->{_Effects}{Eyes} = [];
    GAME->schedule(
      -do   => [$ui, "_eyespawn"],
      -id   => "spawneye",
      -tags => ["map", "ui"],
      -args => [2.5]
    );
    GAME->schedule(
      -do   => [$ui, "_eye"],
      -id   => "eye",
      -tags => ["map", "ui"],
      -args => [0.2]
    );
  } elsif ($effect eq "conveyor") {
    # Set initial state
    UI->_startbelt($_) foreach values %{ GAME->{Map}{Toys}{Conveyors} };
    GAME->schedule(
      -do   => [$ui, "_belt"],
      -id   => "belt",  # TODO: belt bug maybe caused by nonuniqueness here?
      -tags => ["map", "ui"],
      -args => [CFG->{Misc}{BeltSpeed}]
    );
  } elsif ($effect eq "water") {
    $ui->{_Effects}{Water} = [];
    GAME->schedule(
      -do   => [$ui, "water"],
      -id   => "water",
      -tags => ["map", "ui"]
    );
  } elsif ($effect eq "ripples") {
    $ui->{_Effects}{Ripples} = {};
    GAME->schedule(
      -do   => sub {
        my $cnt = scalar(keys %{ $ui->{_Effects}{Ripples} });
        GAME->{Map}{_Data}{ripple_limit} ||= 15;  # And that's already a few ^^;
        # So this limit should depend on the size of the body of water, which is why the
        # map specifies it
        #debug "$cnt ripples currently";
        if ($cnt < GAME->{Map}{_Data}{ripple_limit}) {
          $ui->make_ripple(
            start => choosernd(@{ GAME->{Map}{spawn}{ripples} }),
            iters => GAME->{Map}{_Data}{ripple_life}
          );
        }
        return 1.5;
      },
      -id   => "spawn_ripples",
      -tags => ["map", "ui"]
    );
    GAME->schedule(
      -do   => [$ui, "ripples"],
      -id   => "ripples",
      -tags => ["map", "ui"]
    );
  } else {
    # A particle effect!

    # Determine the effect's bounding box
    my @sets;
    # TODO: this code doesnt NOT work, i just dont remember why im bothering to mark all
    # spots of a smokestack when i just mark the left corner and nuke this code... O_O
    SPAWNPT: foreach (@{ GAME->{Map}{spawn}{$effect} }) {
      my ($y, $x) = @$_;
      # Which set does it belong in?
      foreach my $set (@sets) {
        if ($y == $set->[0] and abs($x - $set->[1] <= 2)) {
          # Even if it belongs, only put it in if they have the smallest X
          $set->[1] = $x if $x < $set->[1];
          next SPAWNPT;
        }
      }
      # New set
      push @sets, [$y, $x];
    }
    foreach (@sets) {
      my ($y, $x) = @$_;
      # TODO: constant values, these
      my $id = scalar keys(%{ GAME->{Map}{Rectangles} }) + 1;
      $id = "fx_$id";
      GAME->{Map}{Rectangles}{$id} = bless {
        Y1     => $y - 7,
        X1     => $x,
        Y2     => $y - 1,
        X2     => $x + 2,
        ID     => $id,
        Effect => $effect,
        List   => []
      }, __PACKAGE__;
    }
  }
}

# We make an effect object and these get called

# Enable our effect
sub on_screen {
  my $effect = shift;
  return if $effect->{Paused};

  # Schedule the two events
  GAME->schedule(
    -do   => [$effect, "_spawn"],
    -id   => "spawn_$effect->{ID}",
    -tags => ["map", "ui", "spawn_$effect->{Effect}"]
  );
  GAME->schedule(
    -do   => [$effect, "_move"],
    -id   => "move_$effect->{ID}",
    -tags => ["map", "ui", "move_$effect->{Effect}"]
  );
}

# Disable our effect
sub off_screen {
  my $effect = shift;

  GAME->unschedule(-actor => $effect);
}

### GONNA MAKE IT SNOW!

# Create a new layer of snow
sub HexedUI::Interface::_snowspawn {
  my $ui = shift;
  my $flakes = $ui->{_Effects}{Flakes};
  my $max = GAME->{Map}->width;
  for (0 .. int($ui->{Main}{Width} / CFG->{Snow}{SpawnWidth})) {
    my $x = $_ * CFG->{Snow}{SpawnWidth};
    next if $x > $max;  # Screen bigger than the map?
    my $period = random(@{ CFG->{Snow}{Period} });
    my $set = random(0, 1);
    push @{ $flakes->[$set]{Flakes} },
      [0, $x, choosernd(-1, 1) * int($period / 2), $period, choosernd(".", "*")];
  }
  return CFG->{Snow}{SpawnRate};
}

# A tick of animation for snowing
sub HexedUI::Interface::_snow {
  my ($ui, $set) = @_;
  my $flakes = $ui->{_Effects}{Flakes};
  my $map = GAME->{Map};
  my $data = $flakes->[$set];

  return 0.5 unless $data;   # Don't get ahead of ourselves... (delay doesnt matter)
  my @flakes = @{ $data->{Flakes} };

  # Erase old flakes relative to the old screen position
  if (defined $data->{OldY}) {
    foreach my $flake (@flakes) {
      my ($y, $x, undef, undef, undef, $bounds) = @$flake;
      next if $bounds;  # Don't need to delete it; it wasn't drawn in the first place
      $y += $data->{OldY};
      $x += $data->{OldX};
      next if $x > $map->width;  # TODO: why do we need this? tmp fix. $bounds?
      $map->del($y, $x, "snow");
    }
  }

  # Current offsets
  my ($y1, $x1) = ($ui->{Main}{OffY}, $ui->{Main}{OffX});
  ($data->{OldY}, $data->{OldX}) = ($y1, $x1);

  # Move them!
  my @new;
  foreach my $flake (@flakes) {
    my ($y, $x, $step, $max, $symbol) = @$flake;
    # Just down for now
    $y++;
    # Now figure out the floaty side-to-side stuff
    if (percent(70)) {
      $step > 0 ? $x++ : $x--;
      if ($step > 0) {
        $step--;
        $step = -1 * $max if $step == 0;
      } else {
        $step++;
        $step = +1 * $max if $step == 0;
      }
    }

    # Is this flake gone and off the screen?
    next if $y >= $ui->{Main}{Height};

    # If it has merely gone off the sides, then don't try to draw it, but keep it in
    # existence
    if ($x < 0 or $x >= $ui->{Main}{Width}) {
      push @new, [$y, $x, $step, $max, $symbol, 1];
    } else {
      push @new, [$y, $x, $step, $max, $symbol];
      $map->mod($y + $y1, $x + $x1, "snow", $symbol, "white");
      #$map->{Heap}{HexedMap}{Pad}->addch($y + $y1, $x + $x1, $ui->{_Prerender}{"Snow$symbol"});
    }
  }
  $data->{Flakes} = \@new;

  $ui->{Main}->drawme;
  return $set == 0 ? CFG->{Snow}{FastSnow} : CFG->{Snow}{SlowSnow};
}

### Particle effects!

sub _spawn {
  my $effect = shift;
  foreach my $x ($effect->{X1} .. $effect->{X2}) {
    #next if percent(30);
    my $life = random(3, 7);
    push @{ $effect->{List} },
      [$effect->{Y2} + 1,
       $x,
       $life,
       choosernd(@{ CFG->{Particles}{ $effect->{Effect} }{Symbol} }),
       CFG->{Particles}{ $effect->{Effect} }{Color}
      ];
  }
  return CFG->{Particles}{ $effect->{Effect} }{Spawn};
}

sub _move {
  my $effect = shift;
  my $map = GAME->{Map};
  my $cfg = CFG->{Particles}{ $effect->{Effect} };

  return $cfg->{Move} unless @{ $effect->{List} };  # Not yet

  # Erase old particles and move them
  my @new;
  foreach (@{ $effect->{List} }) {
    my ($y, $x, $life, $symbol, $color) = @$_;
    $map->del($y, $x, "effect");

    next if $life-- == 0;
    # Plain old up
    $y--;

    next if $y < 0; # Check bounds
    $symbol = $symbol eq $cfg->{Symbol}[0] ? $cfg->{Symbol}[1] : $cfg->{Symbol}[0];
    push @new, [$y, $x, $life--, $symbol, $color];
    $map->mod($y, $x, "effect", $symbol, $color);
    # TODO: no prerendering, then?
  }
  $effect->{List} = \@new;

  UI->{Main}->drawme;
  return $cfg->{Move};
}

### Let EYEBALLS float out of smokestacks!

# Create a new set of eyeballs
sub HexedUI::Interface::_eyespawn {
  my ($ui, $delay) = @_;
  my $eyes = $ui->{_Effects}{Eyes};
  foreach my $spawn (@{ GAME->{Map}{spawn}{eye} }) {
    my $eye = GAME->type("Sprite",
      Shapes => { default => "
 ,--.
(*()*)
 `--'
      "},
      Color => "yellow",
      FloatingBlit => 1,
      Render => {
        "*" => " "
      }
    );
    my $color = random_color();
    $eye->{Shape}[1][$_]{Color} = $color foreach 1 .. $#{ $eye->{Shape}[0] } - 1;
    $eye->{Shape}[3][$_]{Color} = $color foreach 1 .. $#{ $eye->{Shape}[0] } - 1;
    $eye->{Shape}[2][0]{Color} = $eye->{Shape}[2][5]{Color} = $color;
    $eye->{Map} = GAME->{Map};
    $eye->go($spawn->[0] - 4, $spawn->[1] - 2);
    push @$eyes, $eye;
  }
  return $delay;
}

# A tick of animation for eyes
sub HexedUI::Interface::_eye {
  # TODO: technically we need to be in the effect layer
  my ($ui, $delay) = @_;
  my $eyes = $ui->{_Effects}{Eyes};
  my $map = GAME->{Map};

  return $delay unless $eyes;   # Don't get ahead of ourselves

  my @new;
  foreach my $eye (@$eyes) {
    $eye->n;
    next if $eye->{Y} == -4;
    push @new, $eye;
  }
  $ui->{_Effects}{Eyes} = \@new;
  return $delay;
}

# Set initial state
sub HexedUI::Interface::_startbelt {
  my (undef, $belt) = @_;
  my $cnt = 0;
  foreach my $tile ($belt->tiles) {
    my $sym = $cnt++ % 2 ? " " : $belt->{Sym};
    GAME->{Map}->mod(@$tile, symbol => $sym, "grey");
  }
}

# Move the conveyor belt.
sub HexedUI::Interface::_belt {
  my ($ui, $delay) = @_;

  foreach my $belt (values %{ GAME->{Map}{Toys}{Conveyors} }) {
    foreach my $tile ($belt->tiles) {
      my $sym = GAME->{Map}->get(@$tile, "symbol")->[1] eq " " ? $belt->{Sym} : " ";
      GAME->{Map}->overmod(@$tile, symbol => $sym, "grey");
    }
  }
  $ui->{Main}->drawme;
  return $delay;
}

# TODO we're messy. for now, fix the snow bug
sub HexedUI::Interface::clean_fx {
  my $ui = shift;
  my $map = GAME->{Map};
  # Snow, hey oh
  foreach my $set (@{ $ui->{_Effects}{Flakes} }) {
    foreach my $flake (@{ $set->{Flakes} }) {
      my ($y, $x, undef, undef, undef, $bounds) = @$flake;
      next if $bounds;  # Don't need to delete it; it wasn't drawn in the first place
      $y += $set->{OldY};
      $x += $set->{OldX};
      next if $x > $map->width;  # TODO: why do we need this? tmp fix. $bounds?
      $map->del($y, $x, "snow");
    }
  }

  # Water ripples
  foreach my $id (keys %{ $ui->{_Effects}{Ripples} }) {
    my $ripple = $ui->{_Effects}{Ripples}{$id};
    $map->del(@$_, "effect") foreach @{ $ripple->{List} };
    delete $ui->{_Effects}{Ripples}{$id};
  }

  delete $ui->{_Effects};
}

sub HexedUI::Interface::water {
  my $ui = shift;
  my $win = $ui->{Main};
  my ($y1, $x1) = ($win->{OffY}, $win->{OffX});
  my ($y2, $x2) = ($y1 + $win->{Height}, $x1 + $win->{Width});
  my $map = GAME->{Map};
  my $heap = $ui->{_Effects}{Water};

  # Spawning new droplets
  # Find the start of the river, aka search left-right
  LOOK: foreach my $x ($x1 .. $x2) {
    foreach my $y ($y1 .. $y2) {
      my $tile = $map->get($y, $x);
      if ($tile eq "~") {
        push @$heap, [$y, $x];
        last LOOK;
      }
    }
  }

  # Now move everything to the right
  my @new;
  foreach my $drop (@$heap) {
    my ($y, $x) = @$drop;
    # Clean up old
    $map->mod($y, $x, "~") unless $map->feature($y, $x) eq "fakeflood";

    # Reap off-screen ones early
    next if $y < $y1 or $y > $y2 or $x < $x1 or $x > $x2;

    my ($newy, $newx) = (undef, $x + 1);
    MVRIGHT: foreach my $Y (shuffle($y - 1, $y, $y + 1)) {
      my $newt = $map->tile($Y, $newx);
      $newy = $Y, last MVRIGHT if $newt->{_} eq "~" or $map->feature($Y, $newx) eq "fakeflood";
    }

    # Reap or not?
    if ($newy) {
      $map->mod($newy, $newx, "=") unless $map->feature($newy, $newx) eq "fakeflood";
      push @new, [$newy, $newx];
    }
  }
  @$heap = @new;
  #msg see => scalar @new . " drops";

  $win->drawme;
  return 0.2;
}

sub HexedUI::Interface::make_ripple {
  my ($ui, %args) = @_;
  my ($y, $x) = @{ $args{start} };
  $ui->{_Effects}{Ripples}{ tmpcnt() } = {
    Iters => $args{iters},
    Color => $args{color} // "cyan",
    List  => [ [$y, $x] ],
    Old   => { "$y,$x" => 1 },
    Iter  => 0
  };
  GAME->{Map}->mod($y, $x, effect => "~", $args{color});
}

sub HexedUI::Interface::ripples {
  my $ui = shift;
  my $map = GAME->{Map};

  foreach my $id (keys %{ $ui->{_Effects}{Ripples} }) {
    my $self = $ui->{_Effects}{Ripples}{$id};
    my @old = @{ $self->{List} };
    $map->del(@$_, "effect") foreach @old;

    my @new;
    foreach my $old (@old) {
      next unless @$old;  # Wave interference, it's deadly
      # orthog expansion produces diamonds, diag makes boxes... so let's be random ;)
      foreach my $next ($map->adj_tiles(choosernd("diag", "orthog"), @$old)) {
        # Create random breaks. With low percentages, the breaks are usually filled next
        # iteration. This further deforms the blobby.
        next if percent(10);
        my ($y, $x) = @$next;
        next if $self->{Old}{"$y,$x"};  # Don't go backwards
        next unless $map->get($y, $x) eq "~"; # Don't leave the agua

        # Wave interference is simple
        if ($map->get($y, $x, "effect")) {
          # Cancel this particle. The consequence? The wave will reform itself after
          # passing through, but it won't patch the hole immediately. Not phsyically
          # accurate at all, but at a glance, it passes for interference. :)
          #my $bumped = $self->{Map}->tile($y, $x)->{Ripple};
          #$bumped->[0]->unmark($bumped->[1]);
          #@{ $bumped->[1] } = (); # Delete the coords
          next;
        }

        $self->{Old}{"$y,$x"} = 1;
        $map->mod($y, $x, effect => "~", $self->{Color});
        push @new, $next;
      }
    }

    if (!@new or ($self->{Iters} and ++$self->{Iter} == $self->{Iters})) {
      $map->del(@$_, "effect") foreach @new;
      delete $ui->{_Effects}{Ripples}{$id};
    } else {
      $self->{List} = \@new;
    }
  }

  UI->{Main}->drawme;
  return 0.2;
}

42;
