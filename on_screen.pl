#!/usr/bin/env perl


use strict;
use warnings;


use ScreenPlacement;


my $get_screen =
    screen_getter_by_index(
        indexed_rectangles(
            screen_rectangles_from_system(),
        ),
    );


sub produce_result {
    my $spec = shift;

    my $parsed = parse_screen_spec($spec);
    my $screen = $get_screen->($parsed->{screen});
    my $result = place_floating_rect_on_screen($screen, $parsed);
    return $result;
}


my @vars = qw(height width left top);


for (<>) {
    chomp;
    my $result = produce_result($_);
    my ($height, $width, $left, $top) = @$result{@vars};
    print(
        join(' ',
            "-x $left",
            "-y $top",
            "-h $height",
            "-w $width",
            "\n",
        ),
    );
}
