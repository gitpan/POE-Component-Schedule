package POE::Component::Schedule;

use 5.008;

use strict;
use warnings;

our $VERSION = '0.93_01';

use POE;


BEGIN {
    defined &DEBUG or *DEBUG = sub () { 0 };
}

# Properties of a schedule ticket
sub PCS_TIMER     { 0 }  # The POE timer
sub PCS_ITERATOR  { 1 }  # DateTime::Set iterator
sub PCS_SESSION   { 2 }  # POE session ID
sub PCS_EVENT     { 3 }  # Event name
sub PCS_ARGS      { 4 }  # Event args array

# The name of the counter attached to each session
# We use only one counter for all timers of one session
my $refcount_counter_name = __PACKAGE__;

# Scheduling session ID
my $BackEndSession;

# Maps tickets IDs to tickets
my %Tickets = ();
my $LastTicketID = 'a'; # 'b' ... 'z', 'aa' ...

#
# crank up the schedule session
#
sub spawn {
    my $class = shift;
    my %arg   = @_;

    if ( !defined $BackEndSession ) {

        $BackEndSession = POE::Session->create(
            inline_states => {
                _start => sub {
                    print "# $class _start\n" if DEBUG;
                    my ($k) = $_[KERNEL];

                    $k->detach_myself;
                    $k->alias_set( $arg{'Alias'} || $class );
                    $k->sig( 'SHUTDOWN', 'shutdown' );
                },

                schedule     => \&_schedule,
                client_event => \&_client_event,
                cancel       => \&_cancel,

                shutdown => sub {
                    print "# $class shutdown\n" if DEBUG;
                    my $k = $_[KERNEL];

                    # Remove all timers
                    # and decrement session references
                    foreach my $alarm ($k->alarm_remove_all()) {
                        my ($name, $time, $t) = @$alarm;
                        $t->[PCS_TIMER] = undef;
                        $k->refcount_decrement($t->[PCS_SESSION], $refcount_counter_name);
                    }
                    %Tickets = ();

                    $k->sig_handled();
                },
                _stop => sub {
                    print "# $class _stop\n" if DEBUG;
                    $BackEndSession = undef;
                },
            },
        )->ID;
    }
    $BackEndSession
}

#
# schedule the next event
#  ARG0 is the schedule ticket
#
sub _schedule {
    my ( $k, $t ) = @_[ KERNEL, ARG0];

    #
    # deal with DateTime::Sets that are finite
    #
    my $n = $t->[PCS_ITERATOR]->next;
    unless ($n) {
        # No more events, so release the session
        $k->refcount_decrement($t->[PCS_SESSION], $refcount_counter_name);
        $t->[PCS_TIMER] = undef;
        return;
    }

    $t->[PCS_TIMER] = $k->alarm_set( client_event => $n->epoch, $t );
    $t;
}

#
# handle a client event and schedule the next one
#  ARG0 is the schedule ticket
#
sub _client_event {
    my ( $k, $t ) = @_[ KERNEL, ARG0 ];

    $k->post( @{$t}[PCS_SESSION, PCS_EVENT], @{$t->[PCS_ARGS]} );

    _schedule(@_);
}

#
# cancel an alarm
#
sub _cancel {
    my ( $k, $t ) = @_[ KERNEL, ARG0 ];

    if (defined($t->[PCS_TIMER])) {
        $k->alarm_remove($t->[PCS_TIMER]);
        $k->refcount_decrement($t->[PCS_SESSION], $refcount_counter_name);
        $t->[PCS_TIMER] = undef;
    }
    undef;
}

#
# Takes a POE::Session, an event name and a DateTime::Set
# Returns a ticket object
#
sub add {

    my $class  = shift;
    my ( $session, $event, $iterator, @args ) = @_;

    # Remember only the session ID
    $session = ref $session ? $session->ID : $session;

    $iterator->isa('DateTime::Set')
      or die __PACKAGE__ . "->add: third arg must be a DateTime::Set";

    $class->spawn unless $BackEndSession;

    my $id = $LastTicketID++;
    my $ticket = $Tickets{$id} = [
        undef, # Current alarm id
        $iterator,
        $session,
        $event,
        \@args,
    ];

    # We don't want to loose the session until the event has been handled
    $poe_kernel->refcount_increment($session, $refcount_counter_name);

    $poe_kernel->post( $BackEndSession, schedule => $ticket);

    # We return a kind of smart pointer, so the schedule
    # can be simply destroyed by releasing its object reference
    return bless \$id, ref($class) || $class;
}

sub delete {
    my $id = ${$_[0]};
    return unless exists $Tickets{$id};
    $poe_kernel->post($BackEndSession, cancel => delete $Tickets{$id});
}

# Releasing the ticket object will delete the ressource
sub DESTROY {
    $_[0]->delete;
}

{
    no warnings;
    *new = \&add;
}

1;
__END__

=head1 NAME

POE::Component::Schedule - Schedule POE events using DateTime::Set iterators

=head1 SYNOPSIS

    use POE qw(Component::Schedule);
    use DateTime::Set;

    POE::Session->create(
        inline_states => {
            _start => sub {
                $_[HEAP]{sched} = POE::Component::Schedule->add(
                    $_[SESSION], Tick => DateTime::Set->from_recurrence(
                        after      => DateTime->now,
                        before     => DateTime->now->add(seconds => 3),
                        recurrence => sub {
                            return $_[0]->truncate( to => 'second' )->add( seconds => 1 )
                        },
                    ),
                );
            },
            Tick => sub {
                print 'tick ', scalar localtime, "\n";
            },
            remove_sched => sub {
                # Three ways to remove a schedule
                # The first one is only for API compatibility with POE::Component::Cron
                $_[HEAP]{sched}->delete;
                $_[HEAP]{sched} = undef;
                delete $_[HEAP]{sched};
            },
            _stop => sub {
                print "_stop\n";
            },
        },
    );

    POE::Kernel->run();

=head1 DESCRIPTION

This component encapsulates a session that sends events to client sessions
on a schedule as defined by a DateTime::Set iterator.

=head1 POE::Component::Schedule METHODS

=head2 spawn(Alias => I<name>)

No need to call this in normal use, add() and new() all crank
one of these up if it is needed. Start up a PoCo::Schedule. Returns a
handle that can then be added to.

=head2 add()

    my $sched = POE::Component::Schedule->add(
        $session_object,
        $event_name,
        $DateTime_Set_iterator,
        @event_args
    );

Add a set of events to the schedule. The C<$session_object> and C<$event_name> are passed
to POE without even checking to see if they are valid and so have the same
warnings as ->post() itself.
C<$session_object> must be a real L<POE::Session>, not a session ID. Else session
reference count will not be increased and the session may end before receiving all
events.

Returns a schedule handle. The event is removed from when the handle is not referenced
anymore.


=head2 new

new is an alias for add

=head1 SCHEDULE HANDLE METHODS

=head2 delete

Removes a schedule using the handle returned from ->add or ->new.

B<DEPRECATED>: Schedules are now automatically deleted when they are not
referenced anymore. So just setting the container variable to C<undef> will
delete the schedule.

=head1 SEE ALSO

L<POE>, L<DateTime::Set>, L<POE::Component::Cron>.

=head1 BUGS

You can look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-Schedule>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/POE-Component-Schedule>

=item * CPAN Ratings

L<http://cpanratings.perl.org/p/POE-Component-Schedule>

=item * Search CPAN

L<http://search.cpan.org/dist/POE-Component-Schedule/>

=back


=head1 ACKNOWLEDGMENT

This module is a friendly fork of POE::Component::Cron to extract the generic
parts and isolate the Cron specific code in order to reduce dependencies on
other CPAN modules.

The orignal author of POE::Component::Cron is Chris Fedde.

See L<https://rt.cpan.org/Ticket/Display.html?id=44442>

=head1 AUTHORS

=over 4

=item Olivier MenguE<eacute>, C<<< dolmen@cpan.org >>>

=item Chris Fedde, C<<< cfedde@cpan.org >>>

=back

=head1 COPYRIGHT AND LICENSE

=over 4

=item Copyright E<copy> 2007-2008 Chris Fedde

=item Copyright E<copy> 2009 Olivier MenguE<eacute>

=back

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
