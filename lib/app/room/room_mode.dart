enum RoomMode {
  player(null),
  lyrics('lyrics'),
  queue('queue'),
  chat('chat');

  const RoomMode(this.path);

  final String? path;

  String routeIn(String ref) => path == null ? '/r/$ref' : '/r/$ref/$path';
}
