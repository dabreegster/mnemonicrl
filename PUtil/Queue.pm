package PUtil::Queue;

use strict;
use warnings;

use parent "PUtil::Hook";

sub new {
	my ($class, %opts) = @_;
  return bless {
    Queue    => [],
    Active   => 0,
    %opts
  }, $class;
}

sub clear {
  my $self = shift;
  @{ $self->{Queue} } = ();
}

sub get {
  my ($self, $id) = @_;
  return $self->{Queue}[$id];
}

sub active {
  my $self = shift;
  die "No active entry yet... queue is empty\n" unless @{ $self->{Queue} };
  return $self->{Active};
}

sub add {
  my ($self, @new) = @_;
  foreach (@new) {
    push @{ $self->{Queue} }, $_;
    $self->hookshot("add", $_);
  }
}

sub del {
  my ($self, $id) = @_;
  die "$id isnt in the queue!\n" unless defined($self->{Queue}[$id]);
  $self->{Active} = min(0, $self->{Active} - 1) if $id <= $self->{Active};
  my $entry = splice @{ $self->{Queue} }, $id, 1;
  $self->hookshot("del", $entry);
}

sub all {
  my $self = shift;
  return @{ $self->{Queue} };
}

sub howmany {
  my $self = shift;
  return scalar @{ $self->{Queue} };
}

# Changing active entry
sub move {
  my ($self, $to) = @_;
  return if $to < 0 or $to > $#{ $self->{Queue} } or $to == $self->{Active};
  my $old = $self->{Active};
  $self->{Active} = $to;
  $self->hookshot("move", $old);
}

sub move_up {
  my $self = shift;
  $self->move($self->{Active} - 1);
}

sub move_down {
  my $self = shift;
  $self->move($self->{Active} + 1);
}

sub move_first {
  my $self = shift;
  $self->move(0);
}

sub move_last {
  my $self = shift;
  $self->move($#{ $self->{Queue} });
}

# Like a splice, basically
sub insert {
  my ($self, $after, @new) = @_;
  die "Bad insertion pos $after\n" if $after < 0 or $after > $#{ $self->{Queue} };
  splice(@{ $self->{Queue} }, $after, 0, @new);
  $self->hookshot("insert", $_) for $after .. $after + $#new;
}

42;
