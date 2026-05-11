class TrafficSnapshot {
  final int up;
  final int down;
  final int upTotal;
  final int downTotal;
  final int memory;
  final int connections;

  TrafficSnapshot({
    this.up = 0,
    this.down = 0,
    this.upTotal = 0,
    this.downTotal = 0,
    this.memory = 0,
    this.connections = 0,
  });

  /// 内核 up/down 是累计总量，映射到 upTotal/downTotal。
  /// up/down (网速) 由调用方根据差值计算。
  factory TrafficSnapshot.fromKernelJson(Map<String, dynamic> json) => TrafficSnapshot(
    upTotal: (json['up'] as num?)?.toInt() ?? 0,
    downTotal: (json['down'] as num?)?.toInt() ?? 0,
    memory: (json['memory'] as num?)?.toInt() ?? 0,
    connections: (json['connections'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'up': up,
    'down': down,
    'up_total': upTotal,
    'down_total': downTotal,
    'memory': memory,
    'connections': connections,
  };
}

typedef NetSpeed = TrafficSnapshot;
