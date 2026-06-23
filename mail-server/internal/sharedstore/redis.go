package sharedstore

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisStore is the shared-across-instances Store backed by go-redis (R0001 stage 3).
// Keys/TTLs mirror the FileForge/MailAnchor redis_client usage:
//
//	blacklist:{tokenHash}  EX <remaining access lifetime>
//	state:{key}            EX <state ttl>, consumed with GETDEL (single-use)
type RedisStore struct {
	rdb *redis.Client
	// opTimeout bounds each command so a slow/dead Redis cannot hang a request.
	opTimeout time.Duration
}

// Options carries the REDIS_* connection parameters.
type Options struct {
	Host     string
	Port     int
	DB       int
	Password string
	SSL      bool
}

// NewRedisStore dials Redis and verifies the connection with a PING. A dial/ping failure
// returns an error so the caller can fall back to MemStore and log it (boot is never
// blocked by a Redis outage), matching the FileForge-bridge graceful-degradation style.
func NewRedisStore(opt Options) (*RedisStore, error) {
	if opt.Host == "" {
		return nil, errors.New("sharedstore: REDIS_HOST is empty")
	}
	port := opt.Port
	if port == 0 {
		port = 6379
	}
	ro := &redis.Options{
		Addr:     fmt.Sprintf("%s:%d", opt.Host, port),
		Password: opt.Password,
		DB:       opt.DB,
	}
	if opt.SSL {
		ro.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	rdb := redis.NewClient(ro)

	s := &RedisStore{rdb: rdb, opTimeout: 3 * time.Second}
	ctx, cancel := context.WithTimeout(context.Background(), s.opTimeout)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		_ = rdb.Close()
		return nil, fmt.Errorf("sharedstore: redis ping %s: %w", ro.Addr, err)
	}
	return s, nil
}

func (s *RedisStore) ctx() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), s.opTimeout)
}

func (s *RedisStore) Blacklist(tokenHash string, ttl time.Duration) error {
	if ttl <= 0 {
		return nil
	}
	ctx, cancel := s.ctx()
	defer cancel()
	return s.rdb.Set(ctx, blacklistPrefix+tokenHash, "1", ttl).Err()
}

func (s *RedisStore) IsBlacklisted(tokenHash string) (bool, error) {
	ctx, cancel := s.ctx()
	defer cancel()
	n, err := s.rdb.Exists(ctx, blacklistPrefix+tokenHash).Result()
	if err != nil {
		return false, err
	}
	return n > 0, nil
}

func (s *RedisStore) PutState(key, value string, ttl time.Duration) error {
	ctx, cancel := s.ctx()
	defer cancel()
	return s.rdb.Set(ctx, statePrefix+key, value, ttl).Err()
}

func (s *RedisStore) TakeState(key string) (string, bool, error) {
	ctx, cancel := s.ctx()
	defer cancel()
	// GETDEL gives atomic single-use read (Redis 6.2+). A missing key returns redis.Nil.
	v, err := s.rdb.GetDel(ctx, statePrefix+key).Result()
	if errors.Is(err, redis.Nil) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return v, true, nil
}

func (s *RedisStore) Close() error { return s.rdb.Close() }
