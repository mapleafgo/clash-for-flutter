class TrafficSnapshot {
  final int up;
  final int down;
  final int upTotal;
  final int downTotal;
  final int memory;
  final int goroutines;
  final int connsIn;
  final int connsOut;
  final int? startedAt;

  TrafficSnapshot({
    this.up = 0,
    this.down = 0,
    this.upTotal = 0,
    this.downTotal = 0,
    this.memory = 0,
    this.goroutines = 0,
    this.connsIn = 0,
    this.connsOut = 0,
    this.startedAt,
  });

  factory TrafficSnapshot.fromJson(Map<String, dynamic> json) => TrafficSnapshot(
    up: (json['up'] as num?)?.toInt() ?? 0,
    down: (json['down'] as num?)?.toInt() ?? 0,
    upTotal: (json['up_total'] as num?)?.toInt() ?? 0,
    downTotal: (json['down_total'] as num?)?.toInt() ?? 0,
    memory: (json['memory'] as num?)?.toInt() ?? 0,
    goroutines: (json['goroutines'] as num?)?.toInt() ?? 0,
    connsIn: (json['connections_in'] as num?)?.toInt() ?? 0,
    connsOut: (json['connections_out'] as num?)?.toInt() ?? 0,
    startedAt: (json['started_at'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'up': up,
    'down': down,
    'up_total': upTotal,
    'down_total': downTotal,
    'memory': memory,
    'goroutines': goroutines,
    'connections_in': connsIn,
    'connections_out': connsOut,
    'started_at': startedAt,
  };
}

typedef NetSpeed = TrafficSnapshot;
