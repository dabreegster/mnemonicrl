package HexedUI::Cursed::Table;

use strict;
use warnings;
use HexedUI::Util;

# A very simple filter (for Queue so far only) to pad/truncuate title in a tabular fashion

sub new {
  my ($class, %opts) = @_;
  return bless {
    Pad => 2,
    %opts
  }, $class;
}

sub format {
  my ($table, @vars) = @_;
  my $str;
  for (0 .. $#{ $table->{Cols} }) {
    my $col = $table->{Cols}[$_];
    my $sub = shift @vars;
    my $copy = $sub;
    $copy =~ s/<([\w\/]+)>//g;  # Color tags
    my $len = length($copy);
    if ($len > $col) {
      $sub = substr($sub, 0, $col);
    } else {
      # Justify right if last column, looks nicer
      if ($_ == $#{ $table->{Cols} }) {
        $sub = " " x ($col - $len) . $sub;
      } else {
        $sub .= " " x ($col - $len);
      }
    }
    $str .= $sub . " " x $table->{Pad};
  }
  return $str;
}

42;
