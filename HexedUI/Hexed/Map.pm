package HexedUI::Hexed::Map;

# NOTE! dont use us without a BDSM::Map and all the rest of the game engine it pulls in
# from my project mnemonicrl. In this distribution in case anybody wants to see how a 2D
# grid window might work.

use strict;
use warnings;
use HexedUI::Util;

use parent "HexedUI::Cursed::Window";

# Create and return a new menu window.
sub spawn {
  my $self = shift;
  $self->{DrawPad} = 1;
  $self->ui->draw_timed($self);

  $self->bindmap(delete $self->{Opts}{Map}) if $self->{Opts}{Map};
}

# Maps are a bit different... Can't directly tell them to actually redraw to the screen.
# Instead, just request it. That way, frames-per-second can be controlled centrally (and
# internally).
sub drawme {
  my $self = shift;
  $self->{DrawPad} = 1;
}

sub on_resize {
  my ($self, $notrly) = @_;

  # Figure out pad offsets if the map is tiny
  my $map = $self->{Map};
  return unless $map;
  my @offs = ($self->{Y1}, $self->{X1});
  if ($map->height < $self->{Y2} - $self->{Y1} - 1) {
    push @offs, $self->{Y1} + $map->height;
  } else {
    push @offs, $self->{Y2} - 1;
  }
  if ($map->width < $self->{X2} - $self->{X1} - 1) {
    push @offs, $self->{X1} + $map->width;
  } else {
    push @offs, $self->{X2} - 1;
  }
  $self->{Offsets} = \@offs;

  $self->focus unless $notrly;
}

# Bind the window to render a fixed-size map.
sub bindmap {
  my ($self, $map) = @_;

  # If we have a previous map up and the new one is smaller, we need to erase artifacts.
  if ($self->{Pad}) {
    $self->{Pad}->clear;
    $self->windraw;
  }
  $self->{Map}->unhook("HexedMap") if $self->{Map};

  $self->{Map} = $map;
  my ($height, $width) = ($map->height, $map->width);
  $self->{OffY} = $self->{OffX} = 0;
  $self->{CameraOffY} = $self->{CameraOffX} = 0;

  # Make the pad.
  delwin($self->{Pad}) if $self->{Pad}; # Avoid memory leak. Thanks, Bryan Henderson.
  $self->{Pad} = newpad($height + 1, $width + 1);
  # Fill it with the map's initial contents.
  my $initlit = $map->{_Data}{superlight} ? 2 : 0;
  $initlit = $map->{_Data}{initlight} if $map->{_Data}{initlight};
  foreach my $y (0 .. $height) {
    foreach my $x (0 .. $width) {
      $map->{Map}[$y][$x]{Lit} = $initlit; # So I dont get unint value errors later
      my ($sym, $color) = $self->render($map->{Map}[$y][$x]);
      $self->{Pad}->addch($y, $x, ord($sym) | paint($color));
    }
  }

  # Set up a callback.
  $map->hook(HexedMap => $self, sub {
    my $map = shift;
    my $win = shift;
    my $cmd = shift;
    # TODO looky at this interface o_O
    if ($cmd eq "mod") {
      my ($y, $x) = @_; # TODO even though we sometimes get a third, thats fine
      my ($sym, $color) = $self->render( $map->{Map}[$y][$x] );
      $win->{Pad}->addch($y, $x, ord($sym) | paint($color));
    } elsif ($cmd eq "draw") {
      $win->drawme;
    }
  });

  $self->on_resize("notrly");   # We just want pad offsets

  $self->{OnScreen} = {};   # Who can we see right now?
}

# Overloaded... Sort of. We're the method that actually prints to the screen. Through pads.
sub windraw {
  my $self = shift;

  return unless $self->{Pad};

  copywin($self->{Pad}, $self->{Win},
    $self->{OffY}, $self->{OffX},    # Where in the map
    @{ $self->{Offsets} },
    0
  );
}

# Hey, someone could ask. It depends on our Map.
sub mapheight {
  return shift()->{Map}->height;
}

# Hey, someone could ask. It depends on our Map.
sub mapwidth {
  return shift()->{Map}->width;
}

# Shift the camera right.
sub right {
  my $self = shift;
  $self->{OffX}++, $self->refocus if $self->{OffX} <= $self->mapwidth - $self->{Width};
}

# Shift the camera left.
sub left {
  my $self = shift;
  $self->{OffX}--, $self->refocus if $self->{OffX} > 0;
}

# Shift the camera up.
sub up {
  my $self = shift;
  $self->{OffY}--, $self->refocus if $self->{OffY} > 0;
}

# Shift the camera down.
sub down {
  my $self = shift;
  $self->{OffY}++, $self->refocus if $self->{OffY} <= $self->mapheight - $self->{Height};
}

# Modify the camera's offsets to center a sprite.
sub focus {
  my ($self, $sprite, $offy, $offx) = @_;
  if ($sprite) {
    # Set the focus
    $self->{Focus} = $sprite;
  }
  if (defined($offy) or $offx) {
    $self->{CameraOffY} = $offy;
    $self->{CameraOffX} = $offx;
  }
  $sprite = $self->{Focus};
  #die "cant focus if not defined" unless $sprite;
  debug "cant focus if not defined!", return unless $sprite;
  # Just calculate it

  # Dunno where the +1 offset comes from for the upper bound

  my ($Y, $X) = ($sprite->{Y}, $sprite->{X});
  if ($sprite->{Aggregate} != $sprite) {
    # Add blob offset
    $Y += $sprite->{Aggregate}{Y};
    $X += $sprite->{Aggregate}{X};
  }
  $Y += $self->{CameraOffY};
  $X += $self->{CameraOffX};

  my $y = 0;
  $y = $Y - int($self->{Height} / 2);
  $y = $self->mapheight - $self->{Height} + 1 if $y > $self->mapheight - $self->{Height} + 1;
  $y = 0 if $y < 0;   # Lower bound here, upper above. This order is important.

  my $x = 0;
  $x = $X - int($self->{Width} / 2);
  $x = $self->mapwidth - $self->{Width} + 1 if $x > $self->mapwidth - $self->{Width} + 1;
  $x = 0 if $x < 0;   # Lower bound here, upper above. This order is important.

  ($self->{OffY}, $self->{OffX}) = ($y, $x);

  $self->refocus;
}

# Calculate who's going in or out of the screen
sub refocus {
  my $self = shift;
  while (my ($id, $agent) = each %{ $self->{Map}{Agents} }) {
    $self->onscreen($id, $agent);
  }
  while (my ($id, $fx) = each %{ $self->{Map}{Rectangles} }) {
    $self->rect_overlap($id, $fx);
  }
}

# Determine if a particle effect even needs to be rendered right now
sub rect_overlap {
  my ($self, $id, $fx) = @_;
  my $on = 1;
  my ($y, $x) = ($self->{OffY}, $self->{OffX});
  # Offset of 1 for upper bound, so inclusive not exclusive
  # TODO: assumes effect box is smaller than the camera.. lawl i sure hope so
  $on = 0 if $fx->{Y2} < $y or $fx->{Y1} >= $y + $self->{Height};
  $on = 0 if $fx->{X2} < $x or $fx->{X1} >= $x + $self->{Width};

  if ($self->{OnScreen}{$id} and $on == 0) {
    delete $self->{OnScreen}{$id};
    $fx->off_screen;
  } elsif ($on == 1 and !$self->{OnScreen}{$id}) {
    $self->{OnScreen}{$id} = $fx;
    $fx->on_screen;
  }
}

# Determine if an agent is onscreen or not
sub onscreen {
  my ($self, $id, $agent) = @_;
  my $on = 0;
  my ($y, $x) = ($self->{OffY}, $self->{OffX});
  # Offset of 1 for upper bound, so exlusive not inclusive
  $on = 1 if $agent->{Y} >= $y and $agent->{Y} < $y + $self->{Height} and $agent->{X} >= $x and $agent->{X} < $x + $self->{Width};
  $on = 0 unless $agent->tile->{Lit};   # Limit to FOV

  if ($self->{OnScreen}{$id} and $on == 0) {
    delete $self->{OnScreen}{$id};
    $agent->off_screen;
  } elsif ($on == 1 and !$self->{OnScreen}{$id}) {
    $self->{OnScreen}{$id} = $agent;
    $agent->on_screen;
  }
}

# Because we recalculate these a lot.
sub _miny {
  my $self = shift;
  return $self->{OffY};
}

sub _maxy {
  my $self = shift;
  my $y = $self->{OffY} + $self->height - 1;
  $y = $self->{Map}->height if $y > $self->{Map}->height;
  return $y;
}

sub _minx {
  my $self = shift;
  return $self->{OffX};
}

sub _maxx {
  my $self = shift;
  my $x = $self->{OffX} + $self->width - 1;
  $x = $self->{Map}->width if $x > $self->{Map}->width;
  return $x;
}

# Blockingly let the user explore the current cross-section of the map with a cursor,
# performing arbitrary callbacks.
my $targetstate;
sub target {
  my ($self, $args) = args @_;
  my ($refpt, $callback) = ($args->{ref}, $args->{call});

  # Don't return till the user is done playing. So we act like a blocking function.
  $self->ui->start_in;

  my $map = $self->{Map};
  my $y = $refpt->{Y};
  my $x = $refpt->{X};
  $self->_highlight($y, $x);
  $self->drawme;

  # Who's our list of targets?
  $targetstate->{r} = $args->{range};
  $targetstate->{projectile} = $args->{projectile};
  $targetstate->{refpt} = $refpt;
  my @targets;
  my $cur = -1;

  $targetstate->{line} = [];
  #msg err => "Press <cyan>+<Red> to loop through targets"; # TODO we dont know if UI.Msg
  my $act;
  while (1) {
    my $key = $self->ui->wait_input;

    # Did our target move?
    if ($cur != -1 and ($y != $targets[$cur]->{Y} or $x != $targets[$cur]->{X})) {
      ($y, $x) = ($targets[$cur]->{Y}, $targets[$cur]->{X});
    }

    $act = $self->ui->key($key);
    last if $act eq "ok" or $act eq "cancel" or ($act =~ m/^target_/ and !$args->{no_quick});

    $self->target_undraw($y, $x);

    if ($act eq "left") {
      if ($x == $self->_minx) {
        $self->left if $args->{scroll};
      }
      $x--;
    } elsif ($act eq "right") {
      if ($x == $self->_maxx) {
        $self->right if $args->{scroll};
      }
      $x++;
      $x = $self->{Map}->width if $x > $self->{Map}->width;
    } elsif ($act eq "up") {
      if ($y == $self->_miny) {
        $self->up if $args->{scroll};
      }
      $y--;
    } elsif ($act eq "down") {
      if ($y == $self->_maxy) {
        $self->down if $args->{scroll};
      }
      $y++;
      $y = $self->{Map}->height if $y > $self->{Map}->height;
    } elsif ($act eq "next_target") {
      unless ($cur == -1) {
        delete $targets[$cur]->{Targetted};
        $self->target_undraw($targets[$cur]->{Y}, $targets[$cur]->{X});
      }

      # Recalculate target list since people move
      @targets = sort { $a->{ID} <=> $b->{ID} } grep { !$_->{Y2} } values %{ $self->{OnScreen} };
      @targets = grep { !$_->player } @targets if $args->{no_self};
      if ($args->{range}) {
        my @pass;
        foreach (@targets) {
          #next if euclid($refpt->{Y}, $refpt->{X}, $_->{Y}, $_->{X}) > $args->{range};
          next if sqrt(($refpt->{Y} - $_->{Y}) ** 2 + ($refpt->{X} - $_->{X}) ** 2) > $args->{range};
          push @pass, $_;
        }
        @targets = @pass;
      }
      if (@targets) {
        $cur++;
        $cur = 0 if $cur > $#targets;
        $targets[$cur]->{Targetted} = 1;
        ($y, $x) = ($targets[$cur]->{Y}, $targets[$cur]->{X});
      }
    }
    if ($act ne "next_target" and $cur != -1) {
      delete $targets[$cur]->{Targetted};
      $self->target_undraw($targets[$cur]->{Y}, $targets[$cur]->{X});
      $cur = -1;
    }

    # At least do this one so we can't mess with -1 :P
    $y = $self->_miny if $y <= $self->_miny;
    $x = $self->_minx if $x <= $self->_minx;
    my @code = $callback->($self->{Map}, $y, $x, $key);
    ($y, $x) = @code if $code[0] and shift @code eq ":TARGET";

    # Move the cursor if the window moves
    $y = $self->_miny if $y <= $self->_miny;
    $y = $self->_maxy if $y >= $self->_maxy;
    $x = $self->_minx if $x <= $self->_minx;
    $x = $self->_maxx if $x >= $self->_maxx;

    $self->target_draw($y, $x);
  }
  $self->target_undraw($y, $x);
  my $last = $self->{Map}->get($y, $x);
  delete $last->{Targetted} if ref $last;

  $self->ui->stop_in;
  $self->drawme;
  $targetstate = {};

  if ($act =~ s/^target_//) {
    # Just target in a direction as far as we can.
    # TODO diagonals?
    # Messy! But it works.
    my $r = $args->{range} - 1; # Weird bug ^^;
    ($y, $x) = ($refpt->{Y}, $refpt->{X});
    $y -= $r if $act eq "n";
    $y += $r if $act eq "s";
    $x -= $r if $act eq "w";
    $x += $r if $act eq "e";
    $y = 0 if $y < 0;
    $x = 0 if $x < 0;
    $y = $self->{Map}->height if $y > $self->{Map}->height;
    $x = $self->{Map}->width if $x > $self->{Map}->width;
  }

  return ($y, $x);
}

# Also called by BDSM::Agents when they move
sub target_draw {
  my ($self, $y, $x) = @_;
  my $r = $targetstate->{r};
  my $refpt = $targetstate->{refpt};
  # Draw the line
  if ($r) {
    my @effect = @{ $targetstate->{projectile} };
    foreach ($self->{Map}->line($refpt->{Y}, $refpt->{X}, $y, $x, $r)) {
      $self->{Map}->mod(@$_, effect => @effect);
      push @{ $targetstate->{line} }, $_;
    }
  }
  $self->_highlight($y, $x);
  $self->drawme;
}

sub target_undraw {
  my ($self, $y, $x) = @_;
  $self->_unhighlight($y, $x);
  $self->{Map}->del(@$_, "effect") foreach @{ $targetstate->{line} };   # Undraw the line
  $self->drawme;
}

# Highlight a cell and remember its original color.
sub _highlight {
  my ($self, $y, $x) = @_;
  my $map = $self->{Map};
  my $tile = $map->tile($y, $x);

  my ($symbol, $color) = $self->render($tile);

  if ($color) {
    $color =~ s!/\w+!!;
    $color .= "/white";
  } else {
    $color = "grey/white";
  }
  $map->mod($y, $x, "hilite", $symbol, $color);
}

# Return a cell to its original color.
sub _unhighlight {
  my ($self, $y, $x) = @_;
  $self->{Map}->del($y, $x, "hilite");
  # No need to draw because our pair usually does for us
}

# Cast a field-of-view bit around something.
sub light {
  my ($self, $agent) = @_;
  my $map = $agent->{Aggregate}{Map};
  return if $map->{_Data}{superlight};
  my ($r, $newy, $newx) = ($agent->LightSrc, $agent->{Y}, $agent->{X});
  if ($agent->{Aggregate} != $agent) {
    # Add blob offset
    $newy += $agent->{Aggregate}{Y};
    $newx += $agent->{Aggregate}{X};
  }

  my %already;  # Don't unlight stuff we just lit
  
  # Shadowcasting, adapted 
  # http://roguebasin.roguelikedevelopment.org/index.php?title=Ruby_shadowcasting_implementation
  my $matrix = [
    [1,  0,  0, -1, -1,  0,  0,  1],
    [0,  1, -1,  0,  0, -1,  1,  0],
    [0,  1,  1,  0,  0, -1, -1,  0],
    [1,  0,  0,  1, -1,  0,  0, -1]
  ];

  # Track what we're lighting this round so we can be efficient about unlighting
  $map->{AlreadyLit} = { "$newy,$newx" => 1 };

  # Light new stuff
  _cast_light(
    $map, $newy, $newx, 1, 1, 0, $r,
    $matrix->[0][$_], $matrix->[1][$_], $matrix->[2][$_], $matrix->[3][$_],
    2
  ) for 0 .. 7;

  # Unlight old stuff
  if ($agent->{OldLight}) {
    _cast_light(
      $map, @{ $agent->{OldLight} }, 1, 1, 0, $r,
      $matrix->[0][$_], $matrix->[1][$_], $matrix->[2][$_], $matrix->[3][$_],
      1
    ) for 0 .. 7;
  }
  delete $map->{AlreadyLit};
  $agent->{OldLight} = [$newy, $newx];
  
  # Light up player / center
  my $centertile = $map->tile($newy, $newx);
  unless ($centertile->{Lit} == 2) {
    $centertile->{Lit} = 2;
    $map->modded($newy, $newx);
  }
}

sub _cast_light {
  my ($map, $cy, $cx, $row, $light_start, $light_end, $radius, $xx, $xy, $yx, $yy, $mode) = @_;
  return if $light_start < $light_end;
  my $radius_squ = $radius ** 2;

  for my $j ($row .. $radius) {
    my ($dx, $dy) = (0 - $j - 1, 0 - $j);
    my $blocked;
    my $new_start;
    while ($dx <= 0) {
      $dx++;
      my ($mx, $my) = ($cx + $dx * $xx + $dy * $xy, $cy + $dx * $yx + $dy * $yy);
      next unless $map->stfucheck($my, $mx);
      my ($l_slope, $r_slope) = (($dx - 0.5) / ($dy + 0.5), ($dx + 0.5) / ($dy - 0.5));
      next if $light_start < $r_slope;
      last if $light_end > $l_slope;
      if (($dx ** 2) + ($dy ** 2) < $radius_squ) {
        # LIGHT ER UP
        my $tile = $map->tile($my, $mx);
        if ($tile->{Lit} != $mode and !$map->{AlreadyLit}{"$my,$mx"}) {
          # $mode is whether we're lighting or unlighting (so 2 or 1)
          $map->tile($my, $mx)->{Lit} = $mode;
          $map->modded($my, $mx);
        }
        $map->{AlreadyLit}{"$my,$mx"} = 1;
      }
      if ($blocked) {
        if ($map->seethru($my, $mx)) {
          $blocked = 0;
          $light_start = $new_start;
        } else {
          $new_start = $r_slope;
          next;
        }
      } else {
        if (!$map->seethru($my, $mx) and $j < $radius) {
          $blocked = 1;
          _cast_light(
            $map, $cy, $cx, $j + 1, $light_start, $l_slope, $radius,
            $xx, $xy, $yx, $yy, $mode
          );
          $new_start = $r_slope;
        }
      }
    }
    last if $blocked;
  }
}

# Must provide a render that returns ($symbol, $color)!

42;
