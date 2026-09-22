// Rubber Band live pitch/formant shifter with a FIFO that adapts the host's
// variable block size to Rubber Band's fixed one.
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef TV_SHIFTER_H
#define TV_SHIFTER_H

#include <rubberband/RubberBandLiveShifter.h>
#include <cmath>
#include <cstring>
#include <vector>

namespace tv {

class Shifter {
public:
    void init(float sampleRate) {
        rate_ = sampleRate;
        rb_.reset(new RubberBand::RubberBandLiveShifter(
            (size_t)sampleRate, 1,
            RubberBand::RubberBandLiveShifter::OptionWindowShort |
            RubberBand::RubberBandLiveShifter::OptionFormantPreserved));
        block_ = (int)rb_->getBlockSize();
        startDelay_ = (int)rb_->getStartDelay();
        // Four blocks of slack is ample: the host never hands us more than a
        // couple of blocks at a time, and nothing here grows after this point.
        cap_ = block_ * 8;
        inBuf_.assign(cap_, 0.f);
        outBuf_.assign(cap_, 0.f);
        scratchIn_.assign(block_, 0.f);
        scratchOut_.assign(block_, 0.f);
        inFill_ = 0;
        outFill_ = 0;
        pitchSt_ = formantSt_ = 0.f;
        rb_->setPitchScale(1.0);
        rb_->setFormantScale(1.0);
    }

    void setPitchSemitones(float st) {
        if (st == pitchSt_) return;          // avoid needless internal churn
        pitchSt_ = st;
        rb_->setPitchScale(std::pow(2.0, (double)st / 12.0));
    }

    void setFormantSemitones(float st) {
        if (st == formantSt_) return;
        formantSt_ = st;
        rb_->setFormantScale(std::pow(2.0, (double)st / 12.0));
    }

    // Accepts any n. Always writes exactly n samples, emitting zeros while the
    // FIFO primes.
    void process(const float *in, float *out, unsigned long n) {
        unsigned long done = 0;
        while (done < n) {
            // Fill the input FIFO.
            int space = cap_ - inFill_;
            int take = (int)(n - done);
            if (take > space) take = space;
            if (take > 0) {
                std::memcpy(inBuf_.data() + inFill_, in + done, take * sizeof(float));
                inFill_ += take;
            }

            // Consume whole blocks.
            while (inFill_ >= block_ && outFill_ + block_ <= cap_) {
                std::memcpy(scratchIn_.data(), inBuf_.data(), block_ * sizeof(float));
                std::memmove(inBuf_.data(), inBuf_.data() + block_,
                             (inFill_ - block_) * sizeof(float));
                inFill_ -= block_;
                const float *ip[1] = { scratchIn_.data() };
                float *op[1] = { scratchOut_.data() };
                rb_->shift(ip, op);
                std::memcpy(outBuf_.data() + outFill_, scratchOut_.data(),
                            block_ * sizeof(float));
                outFill_ += block_;
            }

            // Drain what the caller asked for.
            int want = (int)(n - done);
            int give = outFill_ < want ? outFill_ : want;
            if (give > 0) {
                std::memcpy(out + done, outBuf_.data(), give * sizeof(float));
                std::memmove(outBuf_.data(), outBuf_.data() + give,
                             (outFill_ - give) * sizeof(float));
                outFill_ -= give;
                done += give;
            } else if (take <= 0) {
                // Nothing taken and nothing to give: pad the rest with silence
                // rather than spin. Only reachable while priming.
                std::memset(out + done, 0, (n - done) * sizeof(float));
                done = n;
            } else {
                std::memset(out + done, 0, (want) * sizeof(float));
                done = n;
            }
        }
    }

    void reset() {
        if (rb_) rb_->reset();
        inFill_ = outFill_ = 0;
        std::fill(inBuf_.begin(), inBuf_.end(), 0.f);
        std::fill(outBuf_.begin(), outBuf_.end(), 0.f);
    }

    int latencySamples() const { return startDelay_ + block_; }
    int blockSize() const { return block_; }

private:
    std::unique_ptr<RubberBand::RubberBandLiveShifter> rb_;
    std::vector<float> inBuf_, outBuf_, scratchIn_, scratchOut_;
    float rate_ = 48000.f, pitchSt_ = 0.f, formantSt_ = 0.f;
    int block_ = 512, startDelay_ = 0, cap_ = 4096, inFill_ = 0, outFill_ = 0;
};

} // namespace tv
#endif
