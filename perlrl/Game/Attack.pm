package Game::Attack;

use strict;
use warnings;
use Util;

sub new {
  my ($class, %dat) = @_;
  return bless { %dat }, $class;
}

# Make an instance of this pattern
sub clone {
  my ($template, @custom_args) = @_;
  my $attack = {};
  foreach (keys %$template) {
    # Don't want Data::Dumper's deep copy, it's not needed
    $attack->{$_} = ref $template->{$_} eq "ARRAY" ? [ @{ $template->{$_} } ] : $template->{$_};
  }
  $attack->{Customize}->($attack, @custom_args) if $attack->{Customize};
  return Game::Attack->new(%$attack);
}

# Resolves ranges. Runs everywhere, recall...
sub range_adj {
  my (undef, $heap, $self, $target) = @_;
  return $self->adj($target) ? $target : ();
}

# TODO check alchemist flood and how it works..
sub range_custom {
  my (undef, $heap, $self, $target, $code) = @_;
  return $code->($heap, $self, $target);
}

# TODO
sub range_FOV {
}

sub range_beam {
  my (undef, $heap, $self, $target, $r) = @_;
  $r = $r->($self) if ref $r eq "CODE";

  my @pts = $self->{Map}->line($self->{Y}, $self->{X}, $target->{Y}, $target->{X}, $r);
  return STOP($self, "Your target can't be reached.") unless @pts;
  $heap->{pts} = \@pts;

  my @pwn = grep { ref $self->{Map}->get(@$_) } @pts;
  $heap->{delay} = CFG->{Misc}{ProjectileLag} * scalar @pts;
  return ( map { $self->{Map}->get(@$_) } @pwn ) if @pwn;
}

# Same as beam, but stop at first target
sub range_fire {
  my (undef, $heap, $self, $target, $r) = @_;
  $r = $r->($self) if ref $r eq "CODE";

  my @pts = $self->{Map}->line($self->{Y}, $self->{X}, $target->{Y}, $target->{X}, $r);
  return STOP($self, "Your target can't be reached.") unless @pts;
  # Cut @pts short if we hit a target before the end
  for (0 .. $#pts) {
    next unless ref $self->{Map}->get(@{ $pts[$_] });
    splice(@pts, $_ + 1);
    last;
  }
  $heap->{pts} = \@pts;

  my @pwn = grep { ref $self->{Map}->get(@$_) } @pts;
  $heap->{delay} = CFG->{Misc}{ProjectileLag} * scalar @pts;
  return $self->{Map}->get(@{ $pwn[0] }) if @pwn;
  return;
}

# Shoot in a line, then explode
sub range_area {
  my (undef, $heap, $self, $target, $r, $expand_iters) = @_;
  $r = $r->($self) if ref $r eq "CODE";

  my @pts = $self->{Map}->line($self->{Y}, $self->{X}, $target->{Y}, $target->{X}, $r);
  @pts = ([$target->{Y}, $target->{X}]) unless @pts;
  # Cut @pts short if we hit a target before the end
  for (0 .. $#pts) {
    next unless ref $self->{Map}->get(@{ $pts[$_] });
    splice(@pts, $_ + 1);
    last;
  }
  $heap->{pts} = \@pts;

  my (@pwn, @rays);

  $self->{Map}->flood(
    -asap      => 1,
    -from      => [ $pts[-1] ],
    -iters     => $expand_iters,
    -dir       => "diag",
    -each_node => sub {
      my ($map, $y, $x) = @_;
      my $tile = $map->get($y, $x);
      push @pwn, $tile if is_obj($tile);
    },
    -each_iter => sub {
      shift;
      push @rays, [@_];
    },
  );
  $heap->{rays} = \@rays;

  $heap->{delay} = CFG->{Misc}{ProjectileLag} * (scalar @pts + scalar @rays);
  return @pwn;
}

# Override us
sub cb_pts {}
sub cb_rays {}
sub cb_targets {}

# Calculate and apply damage to targets
sub damage {
  my ($attack, $heap, $self) = @_;
  foreach my $target (@{ $heap->{targets} }) {
    # Does it hit?
    if ($attack->{HitMiss} and !$attack->{HitMiss}->($self, $target)) {
      $self->saymsg(">battle", "[subj] misses [the 1] with its $attack->{Name} attack!", $target);
      next;
    }

    # Calculate and apply normal damage
    my $pain;
    if ($attack->{DBase}) {
      my $base = $attack->{DBase} * CFG->{Scale}{Damage};
      my $basic = max(0, random($base - CFG->{Scale}{OuchDeviance}, $base + CFG->{Scale}{OuchDeviance}));
      my $level = $self->{Level} * CFG->{Scale}{DRatio};
      my $ac = $target->ac;
      $pain = $basic + max(0, random($level - $ac));
    } elsif ($attack->{Damage}) {
      $pain = int($attack->{Damage}->($self, $target));
    }

    my $death;
    if (defined($pain) and $pain > 0) {
      $death = $target->ouch($pain, $self);
      if ($attack->{Msg}) {
        # TODO pass in $pain as well
        $self->saymsg(">battle", $attack->{Msg}, $target);
      } else {
        $self->saymsg(">battle", "[subj] $attack->{Name}s [the 1] for $pain damage!", $target);
      }
    } elsif (defined($pain)) {
      $self->saymsg(">battle", "[subj] $attack->{Name}s [the 1], harmlessly.", $target);
    }

    unless ($death) {
      my @effects = (qw()); # TODO :P
      foreach (@effects) {
        next unless $attack->{$_};
        $attack->$_($self, $target, @{ $attack->{$_} });
      }
    }
    # We have to do this last, obviously
    $attack->Suicide($self, @{ $attack->{Suicide} }) if $attack->{Suicide};
  }
}




# TODO the lot of this stuff

sub lag {
  my ($atk, $actor) = @_;
  if ($atk->{Lag} eq "weapon") {
    return (CFG->{Scale}{Speed_Max} - $actor->{Equipment}{Weapon}->Accuracy + 1)
      * CFG->{Scale}{SpeedWeapon};
  } else {
    return $atk->{Lag};
  }
}

# Effects:

# TODO theyre still untested

# Zap a stat gradually
sub Drain {
  my ($attack, $self, $target, $stat, $rate, $howlong) = @_;
  if (GAME->fullsim) {
    my $id = "drain$target->{ID}_${stat}_" . tmpcnt;
    $stat = $target->{$stat};
    return if $stat->{Drained}; # Already
    $stat->{Drained} = 1;
    GAME->schedule(
      -do   => sub {
        if ($stat->{Name} eq "HP") {
          # cleanup will cancel us and canceldrain, but then we return here and return a
          # rate, further perpetuating our fur faggotry!
          return "STOP" if $target->ouch(1, $self);
        } else {
          $stat->mod($stat->{Now} - 1);
        }
        return $rate;
      },
      -id   => $id,
      -tags => ["stat_$target->{ID}"],
      -queue => $self->{Map}
    );
    GAME->schedule(
      -do    => sub {
        GAME->unschedule(-id => $id, -queue => $self->{Map});
        delete $stat->{Drained};
        return "STOP";
      },
      -id    => "cancel$id",
      -tags  => ["stat_$target->{ID}"],
      -delay => $howlong,
      -queue => $self->{Map}
    );
  }
  $target->saymsg("[0's] $stat is being drained!");
}

# Prevent a stat from regenerating
sub Inhibit {
  my ($attack, $self, $target, $stat, $howlong) = @_;
  $attack->_timed_fx(
    -onmsg  => [$target, "[0's] $stat won't seem to restore..."],
    -offmsg => [$target, "[0's] $stat begins regenerating again."],
    -set    => [$target->{$stat}, "Inhibited"],
    -delay  => $howlong,
    -tag    => "stat_$target->{ID}",
    -map    => $self->{Map}
  );
}

# Stop movement
sub Paralyze {
  my ($attack, $self, $target, $howlong) = @_;
  $attack->_timed_fx(
    -onmsg  => [$target, "[subj] is paralyzed!"],
    -offmsg => [$target, "[subj] can move again!"],
    -set    => [$target, "Paralyzed"],
    -delay  => $howlong,
    -tag    => "stat_$target->{ID}",
    -map    => $self->{Map}
  );
}

# Stop a target from attacking
sub Infatuate {
  my ($attack, $self, $target, $howlong) = @_;
  $attack->_timed_fx(
    -onmsg  => [$target, "[subj] is too infatuated to attack!"],
    -offmsg => [$target, "[subj] feels normal again!"],
    -set    => [$target, "Infatuated"],
    -delay  => $howlong,
    -tag    => "stat_$target->{ID}",
    -map    => $self->{Map}
  );
}

# Steal an item
sub StealItem {
  my ($attack, $self, $target, $type, $chance) = @_;
  return unless GAME->server;
  return unless percent($chance);

  my $steal = choosernd( grep { $_->is($type) } $target->{Inv}->all );
  return unless $steal;
  # TODO should totally make this a.. action. :P
  GAME->share($self, "local", "all", ["invmv", $steal->{ID}, $self->{ID}]);
  $steal->{Owner}->del($steal);
  $self->saymsg("[subj] steals [1's] [the 2]!", $target, $steal);
  $self->{Inv}->add($steal);
}

# Destroy self after attack
sub Suicide {
  my ($attack, $self, $chance) = @_;
  return unless GAME->server;
  return unless percent($chance);
  $self->saymsg("[subj] destroys itself in a final stand!");
  $self->death(-share => 1, $self);
}

# Summon more monsters
sub Summon {
  my ($attack, $self, $target, $chance, $type, $howmany) = @_;
  return unless GAME->server;

  for (1 .. $howmany) {
    next unless percent($chance);

    my ($y, $x) = ($self->{Y}, $self->{X});
    my $new = GAME->make($type,
      Map => $target->{Map},
      At => [ $self->{Map}->getpt($y - 4, $x - 8, $y + 4, $x + 8) ],
      DontShare => 1
    );
    delete $new->{DontShare};
    GAME->share($self, "local", "all", ["join", $new->serialize]);
  }
}

# Curse an item
sub CurseItem {
  my ($attack, $self, $target, $type, $chance) = @_;
}

# Scatter a party across a dungeon (or two)
sub Scatter {
  my ($attack, $self, $target) = @_;
}

# Force a target to attack its allies
sub Charm {
  my ($attack, $self, $target, $howlong) = @_;
}

# A generic pattern for several effects
sub _timed_fx {
  my (undef, $heap) = @_;
  my ($obj, $attrib) = @{ $heap->{set} };
  return if $obj->{$attrib};  # Don't overkill
  $obj->{$attrib} = 1;
  if (GAME->server) {
    GAME->schedule(
      -do    => sub {
        $heap->{offmsg}[0]->saymsg($heap->{offmsg}[1]);
        delete $obj->{$attrib};
        return "STOP";
      },
      -id    => "cancel${attrib}_" . tmpcnt,
      -tags  => [$heap->{tag}],
      -delay => $heap->{delay},
      -queue => $heap->{map}
    );
  } else {
    $heap->{onmsg}[0]->saymsg($heap->{onmsg}[1]);
  }
}

42;
