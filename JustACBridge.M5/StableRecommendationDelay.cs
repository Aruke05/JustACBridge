namespace JustACBridgeM5;

// Per-held-key debounce for recommendations which are known to flicker.
// A different recommendation clears the delay immediately; returning to the
// delayed recommendation starts a fresh observation window.
internal sealed class StableRecommendationDelay
{
    private int _key;
    private int _delayMs;
    private long _notBeforeTick;

    internal bool Observe(int key, int delayMs, long nowTick)
    {
        if (key <= 0 || delayMs <= 0)
        {
            Reset();
            return true;
        }

        if (_key != key || _delayMs != delayMs)
        {
            _key = key;
            _delayMs = delayMs;
            _notBeforeTick = nowTick + delayMs;
        }

        return nowTick >= _notBeforeTick;
    }

    internal long RemainingMs(long nowTick) => Math.Max(0, _notBeforeTick - nowTick);

    private void Reset()
    {
        _key = 0;
        _delayMs = 0;
        _notBeforeTick = 0;
    }
}
