package Util;

use strict;
use warnings;

# TODO do NOT share UI.. only View:: namespace should be playing with it, after all

use PUtil::Include;

use base "Exporter";
our @EXPORT = (@PUtil::Include::EXPORT, qw( debugs GAME CFG UI Player msg time snooze
               tmpcnt actargs STOP REDIRECT dbug is_obj random_color));

use Cfg;

use Time::HiRes ("time");

# Just print to STDERR
sub debugs {
  print STDERR shift;
}

# Since everything in PerlRL includes us, makes sense for us to do the work of sharing
# variables.
our $share = {
  Player => { ID => -1 }  # Eh, some callbacks trigger before we have a Player
};

# These are convenient interfaces
sub GAME {
  return $share;
}

# My ghetto config interface
sub CFG {
  return $Cfg::cfg;
}

sub UI {
  return $share->{UI};
}

sub Player {
  return $share->{Player};
}

# Do something arbitrary with a message from anywhere.
my $handler;
sub msg ($$) {
  if ($_[0] eq "-set") {
    # Merely pass in an object with an add() and draw() routine conforming to a simple
    # declaration!
    $handler = $_[1];
  } else {
    if ($handler) {
      my ($type, $msg) = @_;
      if (my $color = CFG->{UI}{"${type}Color"}) {
        # GameMsg is usually left grey
        $msg = "<$color>$msg";
      }
      $handler->add($msg);
      $handler->draw;
    } else {
      debug "No msg handler yet, sorry";
    }
  }
}

# TODO log_this overridde to log time

# Like HexedUI's "blocking input", nonblockingly sleep. Use sparingly -- only if timers are
# overkill.
# User must UI->start_in and UI->stop_in to block input.
# TODO: this borks up if we end up pressing a key that invokes a wait_input cause then we
# switch to that loop! So use VERY sparingly.
sub snooze {
  my $stop = time + shift;

  # like dngnor said, this blocks unless there's stuff to do. So ensure there's stuff to
  # do.
  GAME->schedule(
    -do   => sub { 0.1 },
    -id   => "snoozer",
    -tags => ["snooze"]
  );

  POE::Kernel->run_one_timeslice until time >= $stop;
  GAME->unschedule(-id => "snoozer");
}

# Return a temporary number that won't be reused anytime soon. Useful for event IDs.
my $tmpcnt = 0;
sub tmpcnt () {
  return ++$tmpcnt;
}

# Actions right now trade info with a heap
sub actargs {
  my @args;
  push @args, shift;  # $self
  my $heap = shift;
  push @args, $heap, @{ $heap->{Args} };
  return @args;
}

# Halt the flow of events with an excuse perhaps.
sub STOP {
  if (@_) {
    my ($who, @args) = @_;
    $who->saymsg(@args);
  }
  return ":STOP";
}

# Redirect the flow of events to begin a new action entirely.
sub REDIRECT {
  return (":REDIRECT", @_);
}

sub dbug {
  GAME->dbug_cb(@_);
}

# Well? Is it?
# TODO in BDSM::Agent:: and such, not sure whether we want just refs.. those have
# Aggregates cause they're part of Sprites.
sub is_obj {
  my $what = shift;
  return unless ref($what) =~ m/::/;
  return $what->isa("Game::Object");
}

# Just cause
sub random_color {
  return choosernd(
    "blue", "Blue", "red", "Red", "green", "Green", "aqua", "Aqua", "purple", "Purple",
    "orange", "yellow", "grey", "white", "Black"
  );
}

42;
