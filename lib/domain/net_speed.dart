class CoreStats {
  final int up;
  final int down;
  final int upTotal;
  final int downTotal;
  final int memory;
  final int connections;
  final int startedAt;

  CoreStats({
    this.up = 0,
    this.down = 0,
    this.upTotal = 0,
    this.downTotal = 0,
    this.memory = 0,
    this.connections = 0,
    this.startedAt = 0,
  });

  factory CoreStats.fromKernelJson(Map<String, dynamic> json) => CoreStats(
    upTotal: (json['up'] as num?)?.toInt() ?? 0,
    downTotal: (json['down'] as num?)?.toInt() ?? 0,
    memory: (json['memory'] as num?)?.toInt() ?? 0,
    connections: (json['connections'] as num?)?.toInt() ?? 0,
    startedAt: (json['started_at'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'up': up,
    'down': down,
    'up_total': upTotal,
    'down_total': downTotal,
    'memory': memory,
    'connections': connections,
    'started_at': startedAt,
  };
}
