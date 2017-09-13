package ScreenPlacement;

use strict;
use warnings;

use Data::Dumper;
use Carp;
use List::Util qw(min max first);
use List::MoreUtils qw(uniq);
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
    screen_getter_by_index
    parse_screen_spec
    place_floating_rect_on_screen
    indexed_rectangles
    screen_rectangles_from_system
);

sub assign_group_by {
    my $grouper = shift;
    my @lst = @_;

    return { map {$_ => $grouper->($_)} @lst };
}


sub index_ {
    my @lst = @_;
    return {
        map { $lst[$_] => $_ } (0 .. scalar(@lst)-1)
    };
}


sub _rect {
    my $self = shift;
    unless (_validate_as_rect($self)) {
        print Dumper $self;
        confess('Invalid data for constructing a Rect');
    }
    bless $self, 'Rect';
}


sub _validate_as_rect {
    my $r = shift;

    # First, it should be a floating rect (no position)
    return 0 unless _validate_as_floating_rect($r);

    # But it should also have all the needed keys for an actual rect
    my @keys = qw(left top);
    for (@keys) {
        return 0 unless defined $r->{$_};
    }

    # And the values cannot be negative
    for (@keys) {
        return 0 unless $r->{$_} >= 0;
    }

    return 1;
}


sub _float {
    my $self = shift;
    unless (_validate_as_floating_rect($self)) {
        print Dumper $self;
        confess('Invalid data for constructing a FloatingRect');
    }
    bless $self, 'FloatingRect';
}


sub _validate_as_floating_rect {
    my $r = shift;

    # Should have all the needed keys
    my @keys = qw(height width);

    for (@keys) {
        return 0 unless defined $r->{$_};
    }

    # And the values cannot be negative
    for (@keys) {
        return 0 unless $r->{$_} >= 0;
    }

    return 1;
}


# Extract vertical components
sub _top {my $s = shift; $s->{top}}
sub _middle {my $s = shift; ($s->{top} + $s->{height}/2.)}
sub _bottom {my $s = shift; $s->{top} + $s->{height}}
sub _height {my $s = shift; $s->{height}}

# Extract horizontal components
sub _left {my $s = shift; $s->{left}}
sub _center {my $s = shift; ($s->{left} + $s->{width}/2.)}
sub _right {my $s = shift; $s->{left} + $s->{width}}
sub _width {my $s = shift; $s->{width}}


sub _corners {
    my $r = shift;
    return {
        top_left => [_left($r), _top($r)],
        top_right => [_right($r), _top($r)],
        bottom_left => [_left($r), _bottom($r)],
        bottom_right => [_right($r), _bottom($r)],
    };
}


sub _opposite {
    my $corner = shift;
    my $lookup = {
        top_left => 'bottom_right',
        top_right => 'bottom_left',
        bottom_left => 'top_right',
        bottom_right => 'top_left',
    };
    return $lookup->{$corner};
}


sub _rect_from_opposite_corners {
    my %p = (
        # |\|
        top_left => undef,
        bottom_right => undef,
        # |/|
        top_right => undef,
        bottom_left => undef,

        @_,
    );

    # |\|
    if (defined $p{top_left} and defined $p{bottom_right}) {
        return _rect {
            left => $p{top_left}[0],
            top => $p{top_left}[1],
            width => $p{bottom_right}[0] - $p{top_left}[0],
            height => $p{bottom_right}[1] - $p{top_left}[1],
        };

    # |/|
    } elsif (defined $p{top_right} and defined $p{bottom_left}) {
        return _rect {
            left => $p{bottom_left}[0],
            top => $p{top_right}[1],
            width => $p{top_right}[0] - $p{bottom_left}[0],
            height => $p{bottom_left}[1] - $p{top_right}[1],
        };

    # ?
    } else {
        confess('Need top_left and bottom_right or top_right and bottom_left');
    }
}


sub _rect_from_corner_width_height {
    my %p = (
        top_left => undef,
        bottom_right => undef,
        top_right => undef,
        bottom_left => undef,
        width => 0,
        height => 0,
        @_,
    );

    if (defined $p{top_left} and @{$p{top_left}}) {
        my ($x, $y) = @{$p{top_left}};
        return _rect_from_opposite_corners(
            top_left => [$x, $y],
            bottom_right => [$x + $p{width}, $y + $p{height}],
        );

    } elsif (defined $p{top_right} and @{$p{top_right}}) {
        my ($x, $y) = @{$p{top_right}};
        return _rect_from_opposite_corners(
            top_right => [$x, $y],
            bottom_left => [$x - $p{width}, $y + $p{height}],
        );

    } elsif (defined $p{bottom_left} and @{$p{bottom_left}}) {
        my ($x, $y) = @{$p{bottom_left}};
        return _rect_from_opposite_corners(
            bottom_left => [$x, $y],
            top_right => [$x + $p{width}, $y - $p{height}],
        );

    } elsif (defined $p{bottom_right} and @{$p{bottom_right}}) {
        my ($x, $y) = @{$p{bottom_right}};
        return _rect_from_opposite_corners(
            bottom_right => [$x, $y],
            top_left => [$x - $p{width}, $y - $p{height}],
        );

    } else {
        confess('Need to provide coordinates of a corner as an arrayref');
    }
}


# Return a coderef that checks if a point is inside a given rect
sub _point_is_inside {
    my $r = shift;

    return sub {
        my $p = shift;
        my ($x, $y) = @$p;

        return (
            $x >= _left($r) and
            $x <= _right($r) and
            $y >= _top($r) and
            $y <= _bottom($r)
        );
    };
}


sub _zero_rect {
    return {
        left => 0,
        top => 0,
        width => 0,
        height => 0,
    };
}


sub _rect_eq {
    my $r1 = shift;
    my $r2 = shift;

    for (keys %$r1) {
        return 0 unless $r1->{$_} == $r2->{$_};
    }

    return 1;
}


sub _rect_empty {
    my $r = shift;
    return ( $r->{width} == 0 or $r->{height} == 0);
}

sub _rect_nonempty { not _rect_empty(@_) }


sub _overlap {
    my $r1 = shift;
    my $r2 = shift;

    # Take the first corner of r1 that is inside r2.  The corresponding
    # *opposite* corner in r2 will define the other endpoint for the rectangle.

    my $corners_r1 = _corners($r1);
    my $corners_r2 = _corners($r2);

    my $is_inside_r2 = _point_is_inside($r2);

    my $inside_corner =
        first {$is_inside_r2->($corners_r1->{$_})} keys %$corners_r1;

    # Bail with the zero rectangle if they don't overlap
    return _zero_rect() unless $inside_corner;

    my $opposite_corner = _opposite $inside_corner;

    return _rect_from_opposite_corners(
        $inside_corner => $corners_r1->{$inside_corner},
        $opposite_corner => $corners_r2->{$opposite_corner},
    );
}


sub indexed_rectangles {
    my @rectangles = @_;

    # Group the rectangles into equivalent vertical or horizontal coordinates
    my $by_v = assign_group_by(\&_middle, @rectangles);
    my $by_h = assign_group_by(\&_center, @rectangles);

    # Sort the vertical and horizontal values of the equivalence classes and
    # assign them discrete indices
    my @v_values = uniq(values %$by_v);
    my @h_values = uniq(values %$by_h);

    my $v_indices = index_ reverse sort @v_values;
    my $h_indices = index_ reverse sort @h_values;

    my $idx_2d = {
        map {
            my $h_idx = $h_indices->{$by_h->{$_}};
            my $v_idx = $v_indices->{$by_v->{$_}};
            "$h_idx $v_idx" => $_
        } @rectangles
    };

    # A common case is where there is only one row of monitors; then we only
    # need one index.
    #
    # We'll compute the horizontal index here, and decide whether it's
    # appropriate to return it when we return.
    my $idx_1d_hash = {
        map {
            my $h_idx = $h_indices->{$by_h->{$_}};
            $h_idx => $_
        } @rectangles
    };
    my $idx_1d = [ map {$idx_1d_hash->{$_}} sort keys %$idx_1d_hash ];

    # Return the 2d and 1d indices in a list; return undef for the 1d indices
    # if the rects are not all in one row.
    return _rect_array_disjoint(@$idx_1d) ?
        ($idx_1d, $idx_2d) :
        (undef, $idx_2d);
}


sub _rect_array_disjoint {
    my @rects = sort {$a->{left} <=> $b->{left}} @_;
    my @adjacent_overlaps = map {
        _overlap($rects[$_-1], $rects[$_])
    } (1 .. scalar(@rects)-1);

    my $nonempty_overlap = first {_rect_nonempty($_)} @adjacent_overlaps;

    return $nonempty_overlap ? 0 : 1;
}


sub screen_rectangles_from_system {
    # Get the rectangles from the output of xrandr on connected displays
    my @xrandr_connected = split "\n", <<`EOF`;
xrandr
EOF

    my @screen_rectangles = grep {$_} map {
        _rect({
            width => $1,
            height => $2,
            left => $3,
            top => $4,
        }) if m/connected.* (\d+)x(\d+)\+(\d+)\+(\d+)/;
    } @xrandr_connected;

    return wantarray ? @screen_rectangles : [ @screen_rectangles ];
}


sub screen_getter_by_index {
    my ($rd1, $rd2) = @_;

    return sub {
        my $spec = shift;
        chomp $spec;

        if ($spec =~ /^\d+,\d+$/) {
            $spec =~ s/,/ /;
            return $rd2->{$spec};

        } elsif ($spec =~ /^\d+$/) {
            return $rd1->[$spec];

        } else {
            confess("Invalid spec: $spec");
        }
    };
}


sub _screen_spec_from_tuple {
    my ($width_, $height_, $screen_, $hspec, $vspec) = @_;
    return {
        width => $width_,
        height => $height_,
        screen => $screen_,
        hspec => $hspec,
        vspec => $vspec,
    };
}


sub parse_screen_spec {
    my $spec = shift;
    chomp $spec;

    my ($screen, $width, $height, $pos) =
        $spec =~ /^screen((?:\d+)(?:,\d+)?) (\d+)x(\d+) ((?:[\w\d_]+)|(?:\d+,\d+))$/;

    my $ok = (
        defined $screen and
        defined $width and
        defined $height and
        defined $pos
    );
    return {} unless $ok;

    # Explicit provision of H and V percentages
    if ($pos =~ /^(\d+),(\d+)/) {
        return _screen_spec_from_tuple($width, $height, $screen, $1, $2);

    # Corners
    } elsif ($pos =~ /^top_left$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 0, 0);

    } elsif ($pos =~ /^top_right$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 100, 0);

    } elsif ($pos =~ /^bottom_left$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 0, 100);

    } elsif ($pos =~ /^bottom_right$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 100, 100);

    # Centers
    } elsif ($pos =~ /^centered$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 50, 50);

    } elsif ($pos =~ /^top_center$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 50, 0);

    } elsif ($pos =~ /^bottom_center$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 50, 100);

    } elsif ($pos =~ /^middle_left$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 0, 50);

    } elsif ($pos =~ /^middle_right$/i) {
        return _screen_spec_from_tuple($width, $height, $screen, 100, 50);

    # Otherwise, fail
    } else {
        die("Could not parse: $spec");
    }
}


sub place_floating_rect_on_screen {
    my $screen = shift;
    my $spec = shift;

    my ($width_, $height_, $screen_, $hspec, $vspec) =
        @{$spec}{qw(width height screen hspec vspec)};

    my $width = $width_/100 * _width($screen);
    my $height = $height_/100 * _height($screen);

    my ($hradius, $vradius) = ($width/2., $height/2.);

    # Determine how to adjust the position of the float so it doesn't go off
    # the screen
    my $correct_x =
        # left-align
        $hspec < 50 ? 0 :

        # right-align
        $hspec > 50 ? -2*$hradius :

        # center-align
        -$hradius;

    my $correct_y =
        # top-align
        $vspec < 50 ? 0 :

        # bottom-align
        $vspec > 50 ? -2*$vradius :

        # middle-align
        -$vradius;

    return _rect {
        width => $width,
        height => $height,
        left => _left($screen) + ($hspec/100 * _width($screen)) + $correct_x,
        top => _top($screen) + ($vspec/100 * _height($screen)) + $correct_y,
    };
}


1;
