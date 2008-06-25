# Copyright 2008 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3, or (at your option) any later
# version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.


use strict;
use warnings;
use Test::More tests => 10;
use Gtk2::Ex::CrossHair;

ok ($Gtk2::Ex::CrossHair::VERSION >= 1);
ok (Gtk2::Ex::CrossHair->VERSION >= 1);

SKIP: {
  require Gtk2;
  if (! Gtk2->init_check) { skip 'due to no DISPLAY available', 8; }

  # return an arrayref
  sub leftover_fields {
    my ($widget) = @_;
    return [ grep /Gtk2::Ex::CrossHair/, keys %$widget ];
  }

  sub main_iterations {
    my $count = 0;
    while (Gtk2->events_pending) {
      $count++;
      Gtk2->main_iteration_do (0);
    }
    print "main_iterations(): ran $count events/iterations\n";
  }


  # destroyed when weakened on unrealized
  {
    my $widget = Gtk2::Window->new ('toplevel');
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    my $weak_cross = $cross;
    require Scalar::Util;
    Scalar::Util::weaken ($weak_cross);
    $cross = undef;
    main_iterations();
    is ($weak_cross, undef);
    is_deeply (leftover_fields($widget), [],
               'no CrossHair data left behind');
    $widget->destroy;
  }

  # destroyed when weakened on realized
  {
    my $widget = Gtk2::Window->new ('toplevel');
    $widget->realize;
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    my $weak_cross = $cross;
    Scalar::Util::weaken ($weak_cross);
    $cross = undef;
    is ($weak_cross, undef);
    is_deeply (leftover_fields($widget), [],
               'no CrossHair data left behind');
    $widget->destroy;
  }

  # destroyed when weakened on active
  {
    my $widget = Gtk2::Window->new ('toplevel');
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    $widget->show;
    main_iterations();
    $cross->start;
    my $weak_cross = $cross;
    Scalar::Util::weaken ($weak_cross);
    $cross = undef;
    is ($weak_cross, undef);
    is_deeply (leftover_fields($widget), [],
               'no CrossHair data left behind');
    $widget->destroy;
  }

  # start() emits "notify::active"
  {
    my $widget = Gtk2::Window->new ('toplevel');
    $widget->realize;
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    my $seen_notify = 0;
    $cross->signal_connect ('notify::active' => sub { $seen_notify = 1; });
    $cross->start;
    is ($seen_notify, 1);
    $widget->destroy;
  }

  # end() emits "notify::active"
  {
    my $widget = Gtk2::Window->new ('toplevel');
    $widget->realize;
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    $cross->start;
    my $seen_notify = 0;
    $cross->signal_connect ('notify::active' => sub { $seen_notify = 1; });
    $cross->end;
    is ($seen_notify, 1);
    $widget->destroy;
  }
}

exit 0;
