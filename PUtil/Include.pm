package PUtil::Include;

use strict;
use warnings;

use parent "Exporter";
our @EXPORT = qw(
  debug center random roll percent choosernd log_this log_push log_pop slurp args min max
  shuffle clamp
);

use Data::Dumper;
use List::Util ("shuffle"); # TODO everyone have us?

# Data::Dumpers everything it gets to STDERR.
sub debug {
  print STDERR Dumper(@_);
}

# Provide the offset to center something.
sub center {
  my ($thing, $max) = @_;
  $thing = length($thing) unless $thing =~ m/^\d+$/;
  return int($max / 2) - int($thing / 2);
}

# Return a random integer between bounds.
sub random {
  if (@_ == 1) {
    my $max = shift;
    return int rand($max + 1);
  } else {
    my ($min, $max) = @_;
    return $min if $min == $max;
    ($min, $max) = ($max, $min) if $min > $max;
    return int($min + rand($max - $min + 1));
  }
}

# Roll dice in the form "5d6"
sub roll {
  my $roll = shift;
  die "Bad dice form $roll\n" unless $roll =~ m/^(\d+)d(\d+)$/;
  # 3d6+1
  my ($rolls, $sides) = ($1, $2);
  my $sum = 0;
  $sum += random($sides) for 1 .. $rolls;
  return $sum;
}

# Return true a percentage of the time.
sub percent {
  return 1 if random(100) <= shift;
}

# Choose something in a list randomly.
sub choosernd {
  return $_[ random(0, $#_) ];
}

my $logindent = 0;
sub log_push {
  log_this(@_) if @_;
  $logindent++;
}
sub log_pop {
  log_this(@_) if @_;
  if ($logindent) {
    $logindent--;
  } else {
    debug "cant pop log out anymore!", [caller];
    return;
  }
}

# Record a message. Overload to print elsewhere
sub log_this {
  my $msg = shift || "";
  print STDERR " " x ($logindent * 2) . "$msg\n";
}

# External dependencies suck, use us instead
sub slurp {
  my $fn = shift;
  open my $file, $fn or die "Can't open $fn: $!\n";
  my @slurp = <$file>;
  chomp(@slurp);
  close $file;
  return @slurp;
}

# Flexibly handle argument lists with optional named params
sub args {
  my @args;
  push @args, shift;  # $self
  my $opts;
  while (@_ and $_[0] =~ m/^-\D/ and $_[0] =~ m/^-(\w+)$/) {
    shift;
    $opts->{$1} = shift;
  }
  push @args, $opts, @_;  # The rest
  return @args;
}

sub min {
  my ($one, $two) = @_;
  return $one < $two ? $one : $two;
}

sub max {
  my ($one, $two) = @_;
  return $one > $two ? $one : $two;
}

sub clamp {
  my ($what, $min, $max) = @_;
  return $min if $what < $min;
  return $max if $what > $max;
  return $what;
}

42;
