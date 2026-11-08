/// A clock that a test moves by sleeping, so that waits cost no real time.
class FakeTime {
  Duration now = Duration.zero;

  /// Each sleep, in order.
  final List<Duration> sleeps = [];

  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    now += d;
  }

  Duration monotonic() => now;

  Duration get slept => sleeps.fold(Duration.zero, (a, b) => a + b);
}
