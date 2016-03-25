package Game::Stat;

use strict;
use warnings;
use Util;

# TODO: for now, Base is an absolute cap -- no exceeding it yet

sub new {
  my ($class, %opts) = @_;
  my $stat = bless {
    Cap         => $opts{Max},
    RestoreRate => $opts{RestoreRate},
    Now         => $opts{Max},
    Owner       => $opts{Owner}->{ID},
    Name        => $opts{Name}
  }, $class;
 return $stat;
}

# Schedule if necessary
sub start {
  my $stat = shift;
  GAME->schedule(
    -do => [$stat, "restore"],
    -id => "stat_$stat->{Owner}_$stat->{Name}",
    -tags => ["stat_$stat->{Owner}"],
  ) if $stat->{RestoreRate};
}

# Restore the stat slowly
sub restore {
  my $stat = shift;

  $stat->mod($stat->{Now} + 1) unless $stat->{Inhibited};
  return $stat->{RestoreRate};
}

# Temporarily change the stat
sub mod {
  my ($stat, $new) = @_;
  my $old = $stat->{Now};
  $stat->{Now} = $new;
  $stat->{Now} = $stat->{Cap} if $stat->{Now} > $stat->{Cap};
  $stat->modded unless $old == $new;
}

# Change the cap permanently
sub change {
  my ($stat, $new) = @_;
  $stat->{Cap} = $new;
  $stat->{Now} = $stat->{Cap} if $stat->{Now} > $stat->{Cap};   # Re-cap the temp stat
  $stat->modded;
}

# What is it now
sub value {
  return shift()->{Now};
}

# What is its max
sub cap {
  return shift()->{Cap};
}

42;
