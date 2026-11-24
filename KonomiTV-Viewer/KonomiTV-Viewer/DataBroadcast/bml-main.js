// データ放送の重ね合わせのつなぎ。
//
// Web 版 (KonomiTV クライアント) の作りをそのまま移したもの:
// - BML ブラウザの初期化は LiveDataBroadcastingManager.ts と同じ決め事。
//   ただし映像の要素は空の要素を渡し、中に何も入れない (映像の場所が
//   切り抜かれて透明な穴になり、下のネイティブ映像が見える。
//   重ね合わせの検証で実機確認済み)。
// - 材料 (PSI/SI アーカイブデータ) の解き方は、裏方
//   LivePSIArchivedDataDecoder.ts から番組情報を作る部分を除いて
//   書き写したもの。材料の口はアプリ内の中継経由の URL を Swift 側から
//   渡してもらう。
// - 双方向 (ネット接続) は Web 版と同じ形で実装し、実際の通信は
//   アプリ内の中継を通してサーバー側の代理の口へつなぐ。許可が
//   オフのときは、Web 版と同じく「接続していない」の申告にし、
//   一切つながない。
// - 保存データ (NVRAM) は、画面側の保存領域がアプリの再起動を
//   またいで残る保証が無いため、読み書きを Swift 側へ写して控える
//   (橋渡し)。地域情報 (郵便番号・都道府県) は、設定の値を開始時に
//   保存データへ流し込む。
// - 状態 (読み込み中・データ放送の有無・失敗・通信中) は Swift 側へ
//   知らせ、表示はアプリ側の知らせ表示に任せる。
//
// Swift 側からの入口は window.BMLSpike の3つ:
//   start({ psiUrl, serviceId, internetEnabled, proxyBase,
//           zipCode, prefecture, nvram, hasNvram })
//   stop() / sendKey(aribKeyCode)

(function () {
    'use strict';

    var stage = document.getElementById('stage');
    var browser = null;
    var decoder = null;
    var container = null;
    var bmlWidth = 960;
    var bmlHeight = 540;
    // データ放送がそのチャンネルに含まれているか (null: まだ分からない)。
    var availability = null;
    // 双方向の決め事 (開始のたびに Swift 側から渡される)。
    // proxyBase はアプリ内の中継の向き先 (「http://127.0.0.1:ポート」まで)。
    // 中継が使えないときは null で、その場合は通信は失敗の形になる。
    var ipConfig = { internetEnabled: false, proxyBase: null };

    function postStatus(status) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bmlStatus) {
            window.webkit.messageHandlers.bmlStatus.postMessage(status);
        }
    }

    // 解読用の部品 (web-bml の decodeTS) は、材料の中身を読むときに
    // Buffer にしかない読み取りメソッド (readUInt8 など) を使う。
    // Web 版は材料を Buffer に包んで渡しているが、アプリ側では素の
    // Uint8Array のまま渡すため、このままだと最初の包みで例外になる。
    // そこで、解読を始める前に、不足している読み取りメソッドを
    // DataView 経由で Uint8Array に足しておく (符号なし・あり、
    // 8/16/32、大小両端の一式。すでに有るものはそのまま)。
    function installBufferStyleReaders() {
        var readers = {
            readUInt8: function (view, offset) { return view.getUint8(offset); },
            readInt8: function (view, offset) { return view.getInt8(offset); },
            readUInt16LE: function (view, offset) { return view.getUint16(offset, true); },
            readUInt16BE: function (view, offset) { return view.getUint16(offset, false); },
            readInt16LE: function (view, offset) { return view.getInt16(offset, true); },
            readInt16BE: function (view, offset) { return view.getInt16(offset, false); },
            readUInt32LE: function (view, offset) { return view.getUint32(offset, true); },
            readUInt32BE: function (view, offset) { return view.getUint32(offset, false); },
            readInt32LE: function (view, offset) { return view.getInt32(offset, true); },
            readInt32BE: function (view, offset) { return view.getInt32(offset, false); },
        };
        Object.keys(readers).forEach(function (name) {
            if (typeof Uint8Array.prototype[name] === 'function') {
                return;
            }
            var read = readers[name];
            Object.defineProperty(Uint8Array.prototype, name, {
                configurable: true,
                writable: true,
                value: function (offset) {
                    var view = new DataView(this.buffer, this.byteOffset, this.byteLength);
                    return read(view, offset || 0);
                },
            });
        });
    }
    installBufferStyleReaders();

    // MARK: - 材料の解き方 (LivePSIArchivedDataDecoder.ts の書き写し)

    // ヘッダなしの TS パケットにヘッダを設定する
    // EDCB Legacy WebUI の実装をそのまま移植したもの
    function setTSPacketHeader(counters, psiTsPackets, pid) {
        counters[pid] = counters[pid] || 0;
        for (var i = 0; i < psiTsPackets.length; i += 188) {
            psiTsPackets[i] = 0x47;
            psiTsPackets[i + 1] = (i > 0 ? 0 : 0x40) | (pid >> 8);
            psiTsPackets[i + 2] = pid;
            psiTsPackets[i + 3] = 0x10 | counters[pid];
            counters[pid] = (counters[pid] + 1) & 0xf;
        }
    }

    // PSI/SI アーカイブデータを読み込み、PSI/SI TS を生成する
    // EDCB Legacy WebUI の実装をそのまま移植したもの
    // ctx は読み込みの途中経過を持つオブジェクト (空で渡し、関数が中を埋める)
    function readPSIArchivedDataChunk(ctx, buffer, startSecond, callback) {
        var data = new DataView(buffer);

        if (!ctx.pids) {
            ctx.pids = [];
            ctx.dict = [];
            ctx.position = 0;
            ctx.trailer_size = 0;
            ctx.time_list_count = -1;
            ctx.code_list_position = 0;
            ctx.code_count = 0;
            ctx.init_time = -1;
            ctx.curr_time = -1;
        }

        while (data.byteLength - ctx.position >= ctx.trailer_size + 32) {
            var position = ctx.position + ctx.trailer_size;
            var time_list_len = data.getUint16(position + 10, true);
            var dictionary_len = data.getUint16(position + 12, true);
            var dictionary_window_len = data.getUint16(position + 14, true);
            var dictionary_data_size = data.getUint32(position + 16, true);
            var dictionary_buffer_size = data.getUint32(position + 20, true);
            var code_list_len = data.getUint32(position + 24, true);

            if (
                data.getUint32(position) != 0x50737363 ||
                data.getUint32(position + 4) != 0x0d0a9a0a ||
                dictionary_window_len < dictionary_len ||
                dictionary_buffer_size < dictionary_data_size ||
                dictionary_window_len > 65536 - 4096
            ) {
                return null;
            }

            var chunk_size = 32 + time_list_len * 4 + dictionary_len * 2 + Math.ceil(dictionary_data_size / 2) * 2 + code_list_len * 2;

            if (data.byteLength - position < chunk_size) break;

            var time_list_position = position + 32;
            position += 32 + time_list_len * 4;

            if (ctx.time_list_count < 0) {
                var pids = [];
                var dict = [];
                var section_list_position = 0;

                for (var i = 0; i < dictionary_len; i++, position += 2) {
                    var code_or_size = data.getUint16(position, true) - 4096;
                    if (code_or_size >= 0) {
                        if (code_or_size >= ctx.pids.length || ctx.pids[code_or_size] < 0) {
                            return null;
                        }
                        pids[i] = ctx.pids[code_or_size];
                        dict[i] = ctx.dict[code_or_size];
                        ctx.pids[code_or_size] = -1;
                    } else {
                        pids[i] = code_or_size;
                        dict[i] = null;
                        section_list_position += 2;
                    }
                }
                section_list_position += position;

                for (var j = 0; j < dictionary_len; j++) {
                    if (pids[j] >= 0) {
                        continue;
                    }
                    var psi = new Uint8Array(data.buffer, section_list_position, pids[j] + 4097);
                    dict[j] = new Uint8Array(Math.ceil((psi.length + 1) / 184) * 188);
                    for (var k = 0, l = 0; l < psi.length; k++, l++) {
                        if (!(k % 188)) {
                            k += 4;
                            if (!l) {
                                dict[j][k++] = 0;
                            }
                        }
                        dict[j][k] = psi[l];
                    }
                    section_list_position += psi.length;
                    pids[j] = data.getUint16(position, true) & 0x1fff;
                    position += 2;
                }

                for (var m = dictionary_len, n = 0; m < dictionary_window_len; n++) {
                    if (n >= ctx.pids.length) return null;
                    if (ctx.pids[n] < 0) continue;
                    pids[m] = ctx.pids[n];
                    dict[m++] = ctx.dict[n];
                }
                ctx.pids = pids;
                ctx.dict = dict;
                ctx.time_list_count = 0;
                position = section_list_position + dictionary_data_size % 2;
            } else {
                position += dictionary_len * 2 + Math.ceil(dictionary_data_size / 2) * 2;
            }

            position += ctx.code_list_position;
            time_list_position += ctx.time_list_count * 4;
            for (; ctx.time_list_count < time_list_len; ctx.time_list_count++, time_list_position += 4) {
                var init_time = ctx.init_time;
                var curr_time = ctx.curr_time;
                var abs_time = data.getUint32(time_list_position, true);
                if (abs_time === 0xffffffff) {
                    curr_time = -1;
                } else if (abs_time >= 0x80000000) {
                    curr_time = abs_time & 0x3fffffff;
                    if (init_time < 0) {
                        init_time = curr_time;
                    }
                } else {
                    var count = data.getUint16(time_list_position + 2, true) + 1;
                    if (curr_time >= 0) {
                        curr_time += data.getUint16(time_list_position, true);
                        var sec = ((curr_time + 0x40000000 - init_time) & 0x3fffffff) / 11250;
                        if (sec >= (startSecond || 0)) {
                            for (; ctx.code_count < count; ctx.code_count++, position += 2, ctx.code_list_position += 2) {
                                var code = data.getUint16(position, true) - 4096;
                                callback(sec, ctx.dict[code], ctx.pids[code]);
                            }
                            ctx.code_count = 0;
                        } else {
                            position += count * 2;
                            ctx.code_list_position += count * 2;
                        }
                    } else {
                        position += count * 2;
                        ctx.code_list_position += count * 2;
                    }
                }
                ctx.init_time = init_time;
                ctx.curr_time = curr_time;
            }

            ctx.position = position;
            ctx.trailer_size = 2 + (2 + chunk_size) % 4;
            ctx.time_list_count = -1;
            ctx.code_list_position = 0;
            ctx.curr_time = -1;
        }
        var ret = data.buffer.slice(ctx.position);
        ctx.position = 0;
        return ret;
    }

    // 材料の流れを受け取り、解いて BML ブラウザへ渡す係。
    // onMessage には Web 版の decoded_callback と同じ形で、
    // decodeTS の結果と PCR の合図が届く。
    // onError は、材料の口への接続自体が失敗したときだけ呼ばれる
    // (Web 版は無言だが、アプリでは失敗が見えた方が確かめやすいため)。
    function createDecoder(serviceId, onMessage, onError) {
        var tsStream = decodeTS({
            sendCallback: function (message) { onMessage(message); },
            serviceId: serviceId,
            // ARIB 字幕は PES に含まれるため PES パケットをパースする必要があるが、ここでは無効化 (Web 版と同じ)
            parsePES: false,
        });
        var archived = new Uint8Array(0);
        var ctx = {};
        var counters = {};
        var abortController = null;
        var lastPcr = -1;
        var destroyed = false;

        return {
            run: function (url) {
                abortController = new AbortController();
                fetch(url, { signal: abortController.signal }).then(async function (response) {
                    var reader = (response.body !== null && response.body !== undefined) ? response.body.getReader() : undefined;
                    if (reader === undefined || response.ok === false) {
                        onError();
                        return;
                    }
                    while (true) {
                        var result = await reader.read();
                        if (result.done) {
                            break;
                        }
                        var addData = result.value;
                        var concatData = new Uint8Array(archived.length + addData.length);
                        concatData.set(archived);
                        concatData.set(addData, archived.length);
                        var rest = readPSIArchivedDataChunk(ctx, concatData.buffer, 0, function (second, packets, pid) {
                            // PCR (Packet Clock Reference) を取得して送信
                            var pcr = Math.floor(second * 90000);
                            if (lastPcr !== pcr) {
                                onMessage({
                                    type: 'pcr',
                                    pcrBase: pcr,
                                    pcrExtension: 0,
                                });
                                lastPcr = pcr;
                            }
                            // TS パケットのヘッダを設定してデコード
                            // (解読で例外が出ても、材料の受け取り全体を
                            // 失敗にしないための守り)
                            setTSPacketHeader(counters, packets, pid);
                            try {
                                tsStream.parse(packets);
                            } catch (e) {
                                // この包みの解読だけを飛ばして続ける
                            }
                        });
                        if (rest) {
                            archived = new Uint8Array(rest);
                        }
                    }
                }).catch(function (error) {
                    // 中断 (終了操作) のときは何もしない (Web 版と同じ)。
                    // それ以外の接続の失敗は、アプリで見えるよう知らせる。
                    if (destroyed === false && (error === undefined || error === null || error.name !== 'AbortError')) {
                        onError();
                    }
                });
            },
            destroy: function () {
                destroyed = true;
                if (abortController !== null) {
                    abortController.abort();
                    abortController = null;
                }
                archived = new Uint8Array(0);
                ctx = {};
                counters = {};
            },
        };
    }

    // MARK: - 映像の窓の切り抜きの付け直し (穴が白くなる件の直し)

    // 描く仕組み (web-bml) は、地の要素 (arib-bg) と背景の静止画の要素に
    // 映像の窓の形の切り抜き (clip-path) を付けて、窓の場所だけ下を
    // 透かす作りになっている。ところが iPhone の WebView の中では
    // その切り抜きが効かず、地の色 (NHK では真っ白) が窓の場所まで
    // 塗ってしまう (拡張版0.59の実機で確認済み)。
    // そこで、文書が開くたびと映像の窓が変わるたびに、つなぎから
    // 同じ形の切り抜きを、通常の指定 (clip-path) と iPhone 向けの
    // 旧式の指定 (-webkit-clip-path) の両方で入れ直す。
    // 形の作り方と対象の選び方は web-bml の clipVideoPlane と同じ。
    // 影の領域 (閉じた shadow root) には、描く仕組みが自分で持って
    // いる控え (browser.shadowRoot) からたどり着く。

    // 窓の四角から、切り抜きの形 (地を窓の形にくり抜く多角形) を作る。
    function buildVideoPlaneClipPath(rect) {
        return 'polygon(0% 0%, 0% 100%, ' + rect.left + 'px 100%, ' + rect.left + 'px ' + rect.top + 'px, '
            + rect.right + 'px ' + rect.top + 'px, ' + rect.right + 'px ' + rect.bottom + 'px, '
            + rect.left + 'px ' + rect.bottom + 'px, ' + rect.left + 'px 100%, 100% 100%, 100% 0%)';
    }

    // 切り抜きを、通常の指定と旧式の指定の両方で入れる。
    function setClipPathBoth(element, value) {
        element.style.setProperty('clip-path', value);
        element.style.setProperty('-webkit-clip-path', value);
        try {
            element.style.clipPath = value;
        } catch (e) {
            // 直接の代入ができない環境では、上の指定だけで足りる
        }
    }

    // 要素の場所を、文書の body からの相対の四角で返す
    // (web-bml の getRect と同じ数え方)。
    function getRectFromBody(body, element) {
        var left = 0;
        var top = 0;
        var current = element;
        while (current !== null && current !== body) {
            left += current.offsetLeft;
            top += current.offsetTop;
            current = current.parentElement;
        }
        return { left: left, top: top, right: left + element.clientWidth, bottom: top + element.clientHeight };
    }

    // 2つの四角の重なりを返す (重ならなければ null。web-bml と同じ)。
    function intersectRect(rect1, rect2) {
        if (rect1.left < rect2.right && rect2.left < rect1.right && rect1.top < rect2.bottom && rect2.top < rect1.bottom) {
            return {
                left: Math.max(rect1.left, rect2.left),
                right: Math.min(rect1.right, rect2.right),
                top: Math.max(rect1.top, rect2.top),
                bottom: Math.min(rect1.bottom, rect2.bottom),
            };
        }
        return null;
    }

    // MARK: - 映像の窓の場所を Swift 側へ知らせる (字幕を窓の中に収めるため)

    // 直近に分かった映像の窓の四角 (body からの相対)。
    var lastVideoRect = null;

    // 窓の四角を、画面 (WebView の表示範囲) の大きさに対する割合の
    // 四角に直して Swift 側へ送る。Swift 側はこの割合で、字幕の
    // 重ね物を窓の中だけに収める (本物のテレビで、字幕が映像と
    // 一緒に縮んで窓の中に出る扱いに合わせる)。
    // rect が null のときは「窓の指定なし (映像全体に戻す)」として送る。
    function postVideoRect(rect) {
        if (!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bmlVideoRect)) {
            return;
        }
        if (rect === null) {
            window.webkit.messageHandlers.bmlVideoRect.postMessage(null);
            return;
        }
        if (window.innerWidth <= 0 || window.innerHeight <= 0) {
            return;
        }
        // 文書の座標から画面の座標への写し方は、置き場の拡大率の計算
        // (calculateScaleFactor) と同じ。置き場は画面の中央に置かれ、
        // 文書の中心が画面の中心に重なる。
        var scaleFactor = Math.min(
            window.innerWidth / (bmlHeight * 16 / 9),
            window.innerHeight / bmlHeight);
        var sx = scaleFactor * ((bmlHeight * 16 / 9) / bmlWidth);
        var sy = scaleFactor;
        var originX = (window.innerWidth - bmlWidth * sx) / 2;
        var originY = (window.innerHeight - bmlHeight * sy) / 2;
        window.webkit.messageHandlers.bmlVideoRect.postMessage({
            left: (originX + rect.left * sx) / window.innerWidth,
            top: (originY + rect.top * sy) / window.innerHeight,
            width: ((rect.right - rect.left) * sx) / window.innerWidth,
            height: ((rect.bottom - rect.top) * sy) / window.innerHeight,
        });
    }

    // 画面の大きさが変わったら (回転や全画面への貸し出し)、
    // 同じ窓の四角で割合を送り直す。
    window.addEventListener('resize', function () {
        if (lastVideoRect !== null) {
            postVideoRect(lastVideoRect);
        }
    });

    // 地の要素と背景の静止画の要素へ、切り抜きを入れ直す。
    // knownRect には、videochanged の知らせに含まれる窓の四角
    // (body からの相対) があればそれを使う。無ければ要素の場所から数える。
    // 失敗してもデータ放送自体は止めない (付け直しは上乗せの直しのため)。
    function reapplyVideoPlaneClip(knownRect) {
        try {
            if (browser === null) {
                return;
            }
            var root = browser.shadowRoot;
            if (!root) {
                return;
            }
            var body = root.querySelector('body');
            if (body === null) {
                return;
            }
            var aribBG = body.querySelector('arib-bg');
            var videoElement = body.querySelector('[arib-type="video/X-arib-mpeg2"]');
            if (aribBG === null || videoElement === null) {
                return;
            }
            var videoRect = knownRect || getRectFromBody(body, videoElement);
            // 窓の場所が分かったので、字幕を窓の中に収めるために
            // Swift 側へも知らせる。
            lastVideoRect = videoRect;
            postVideoRect(videoRect);
            setClipPathBoth(aribBG, buildVideoPlaneClipPath(videoRect));
            // 背景の静止画 (映像より後ろにある image/jpeg の object) にも、
            // 窓と重なる部分だけ同じ切り抜きを入れ直す (web-bml と同じ選び方)。
            var bgJpegs = Array.prototype.slice.call(body.querySelectorAll('object[arib-type="image/jpeg"]')).filter(function (x) {
                return (x.compareDocumentPosition(videoElement) & Node.DOCUMENT_POSITION_FOLLOWING) === Node.DOCUMENT_POSITION_FOLLOWING;
            });
            bgJpegs.forEach(function (bgJpeg) {
                var jpegRect = getRectFromBody(body, bgJpeg);
                var intersect = intersectRect(videoRect, jpegRect);
                if (intersect !== null) {
                    setClipPathBoth(bgJpeg, buildVideoPlaneClipPath({
                        left: intersect.left - jpegRect.left,
                        right: intersect.right - jpegRect.left,
                        top: intersect.top - jpegRect.top,
                        bottom: intersect.bottom - jpegRect.top,
                    }));
                } else {
                    setClipPathBoth(bgJpeg, '');
                }
            });
        } catch (e) {
            // 付け直しの失敗でデータ放送を止めない
        }
    }

    // 文書が開いた直後は要素の場所がまだ定まっていないことがあるため、
    // 少し置いてからもう一度入れ直す。
    function scheduleVideoPlaneClipReapply() {
        if (typeof requestAnimationFrame === 'function') {
            requestAnimationFrame(function () { reapplyVideoPlaneClip(null); });
        }
        setTimeout(function () { reapplyVideoPlaneClip(null); }, 300);
    }

    // MARK: - 保存データ (NVRAM) の橋渡し

    // 保存データの保存領域のキーの接頭辞 (BML ブラウザの決め事:
    // storagePrefix + nvramPrefix)。
    var NVRAM_KEY_PREFIX = 'KonomiTV-BMLBrowser_nvram_';
    // 地域情報の保存先のキーの土台 (Web 版の設定画面が書く形と同じ)。
    var RECEIVER_INFO_KEY_BASE = 'KonomiTV-BMLBrowser_nvram_prefix=receiverinfo%2F';
    var nvramBridgeInstalled = false;

    // 保存領域にある保存データのキーを、キー → 値の辞書で全部読む。
    function readAllNvram() {
        var result = {};
        try {
            for (var i = 0; i < window.localStorage.length; i++) {
                var key = window.localStorage.key(i);
                if (key !== null && key.indexOf(NVRAM_KEY_PREFIX) === 0) {
                    result[key] = window.localStorage.getItem(key);
                }
            }
        } catch (e) {
            // 保存領域に触れない環境では空で受ける
        }
        return result;
    }

    // 保存データの今の写しを Swift 側へ送る (アプリ側の控えになる)。
    function postNvram() {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bmlNvram) {
            window.webkit.messageHandlers.bmlNvram.postMessage(readAllNvram());
        }
    }

    // 保存領域への書き込みを横取りし、保存データのキーが変わるたびに
    // Swift 側へ写しを送る。これで、データ放送の中で溜まった保存データが
    // アプリ側の控えに残る。
    function installNvramBridge() {
        if (nvramBridgeInstalled) {
            return;
        }
        nvramBridgeInstalled = true;
        try {
            var proto = window.Storage.prototype;
            var originalSetItem = proto.setItem;
            var originalRemoveItem = proto.removeItem;
            var originalClear = proto.clear;
            proto.setItem = function (key, value) {
                originalSetItem.call(this, key, value);
                if (this === window.localStorage && String(key).indexOf(NVRAM_KEY_PREFIX) === 0) {
                    postNvram();
                }
            };
            proto.removeItem = function (key) {
                originalRemoveItem.call(this, key);
                if (this === window.localStorage && String(key).indexOf(NVRAM_KEY_PREFIX) === 0) {
                    postNvram();
                }
            };
            proto.clear = function () {
                originalClear.call(this);
                if (this === window.localStorage) {
                    postNvram();
                }
            };
        } catch (e) {
            // 横取りできなくても、開始時の吸い上げと流し込みは行う
        }
    }

    // 開始時の保存データの用意。アプリ側に控えがあれば画面側の保存領域を
    // 控えと一致させ (リセットの反映もここで効く)、控えがまだ無ければ
    // 画面側に残っている分を吸い上げて控えにする (検証版までで溜まった
    // 保存データを引き継ぐため)。そのあと、地域情報 (郵便番号・都道府県)
    // を保存データへ流し込む。
    function prepareNvram(config) {
        installNvramBridge();
        try {
            if (config.hasNvram) {
                var snapshot = config.nvram || {};
                var existing = readAllNvram();
                Object.keys(existing).forEach(function (key) {
                    if (!(key in snapshot)) {
                        window.localStorage.removeItem(key);
                    }
                });
                Object.keys(snapshot).forEach(function (key) {
                    if (existing[key] !== snapshot[key]) {
                        window.localStorage.setItem(key, snapshot[key]);
                    }
                });
            }
            applyReceiverInfo(config.zipCode || '', config.prefecture || '');
            // 流し込みまで終えた状態を、アプリ側の控えとして送る
            // (初回の吸い上げも兼ねる)。
            postNvram();
        } catch (e) {
            // 保存データの用意ができなくても、データ放送自体は続ける
        }
    }

    // 地域情報を保存データへ流し込む。符号化は Web 版の設定画面
    // (DataBroadcasting.vue) が保存データへ書く形とまったく同じ。
    function applyReceiverInfo(zipCode, prefectureValue) {
        if (zipCode) {
            // ハイフンを除いて Base64 符号化する
            window.localStorage.setItem(
                RECEIVER_INFO_KEY_BASE + 'zipcode', window.btoa(zipCode.replace('-', '')));
        } else {
            window.localStorage.removeItem(RECEIVER_INFO_KEY_BASE + 'zipcode');
        }
        var applied = false;
        if (prefectureValue && prefectureValue !== '255-0b0') {
            var parts = prefectureValue.split('-0b');
            var prefectureNumber = parseInt(parts[0], 10);
            var regionCodeNumber = parseInt(parts[1], 2);
            if (!isNaN(prefectureNumber) && !isNaN(regionCodeNumber)) {
                window.localStorage.setItem(
                    RECEIVER_INFO_KEY_BASE + 'prefecture',
                    window.btoa(String.fromCharCode(prefectureNumber)));
                window.localStorage.setItem(
                    RECEIVER_INFO_KEY_BASE + 'regioncode',
                    window.btoa(String.fromCharCode(regionCodeNumber >> 8, regionCodeNumber & 0xff)));
                applied = true;
            }
        }
        if (!applied) {
            window.localStorage.removeItem(RECEIVER_INFO_KEY_BASE + 'prefecture');
            window.localStorage.removeItem(RECEIVER_INFO_KEY_BASE + 'regioncode');
        }
    }

    // 双方向の通信先 (サーバー側の代理の口) を、アプリ内の中継経由の
    // URL にする。中継が使えないときは null。
    function proxyURL(path) {
        return ipConfig.proxyBase !== null ? ipConfig.proxyBase + path : null;
    }

    // MARK: - BML ブラウザまわり

    // データ放送画面の拡大/縮小率を再計算し、CSS カスタムプロパティに設定する
    // (LiveDataBroadcastingManager.calculateBMLBrowserScaleFactor の書き写し。
    // 入れる先の大きさは、この画面 (映像の枠) の大きさ)
    function calculateScaleFactor() {
        if (container === null) {
            return;
        }
        var scaleFactorWidth = window.innerWidth / (bmlHeight * 16 / 9);
        var scaleFactorHeight = window.innerHeight / bmlHeight;
        var scaleFactor = Math.min(scaleFactorWidth, scaleFactorHeight);
        var magnification = (bmlHeight * 16 / 9) / bmlWidth;
        container.style.setProperty('--bml-browser-scale-factor-width', String(scaleFactor * magnification));
        container.style.setProperty('--bml-browser-scale-factor-height', String(scaleFactor));
    }
    window.addEventListener('resize', calculateScaleFactor);

    // Greg: 受信機の電源を切るまで持続するメモリ (Web 版と同じ置き場所)
    var gregImpl = {
        getReg: function (index) {
            var stored = window.sessionStorage.getItem('KonomiTV-BMLBrowser-Greg');
            var greg = stored === null ? new Array(64).fill('') : JSON.parse(stored);
            return greg[index] ?? '';
        },
        setReg: function (index, value) {
            var stored = window.sessionStorage.getItem('KonomiTV-BMLBrowser-Greg');
            var greg = stored === null ? new Array(64).fill('') : JSON.parse(stored);
            greg[index] = value;
            window.sessionStorage.setItem('KonomiTV-BMLBrowser-Greg', JSON.stringify(greg));
        },
    };

    function start(config) {
        stopInternal();
        postStatus('loading');
        availability = null;

        // 置き場は開始のたびに新しい要素にする (BML ブラウザは置き場に
        // 影の領域を作るため、同じ要素への作り直しができない)。
        container = document.createElement('div');
        container.className = 'bml-container';
        stage.appendChild(container);
        bmlWidth = 960;
        bmlHeight = 540;
        container.style.setProperty('--bml-browser-width', bmlWidth + 'px');
        container.style.setProperty('--bml-browser-height', bmlHeight + 'px');
        calculateScaleFactor();

        // 双方向の決め事と保存データの用意は、BML ブラウザを作る前に済ませる
        // (保存データは文書の読み込み時点で読まれるため)。
        ipConfig = {
            internetEnabled: !!config.internetEnabled,
            proxyBase: config.proxyBase || null,
        };
        prepareNvram(config);

        browser = new BMLBrowser({
            // 映像の要素は空の要素を渡し、中に何も入れない。
            // 映像の場所は切り抜かれて透明な穴になり、下の映像が見えるはず。
            mediaElement: document.createElement('div'),
            containerElement: container,
            storagePrefix: 'KonomiTV-BMLBrowser_',
            nvramPrefix: 'nvram_',
            broadcasterDatabasePrefix: '',
            videoPlaneModeEnabled: true,
            fonts: {
                roundGothic: { source: 'url("KosugiMaru-Regular.woff2"), local("sans-serif")' },
                squareGothic: { source: 'url("Kosugi-Regular.woff2"), local("sans-serif")' },
            },
            indicator: {
                // 通信の始まりと終わりを Swift 側へ知らせる
                // (リモコンの読み込み中の表示に使う。Web 版も同じ
                // 知らせでリモコンの読み込み状態を切り替えている)。
                setUrl: function (name, loading) { postStatus(loading ? 'netbusy' : 'netidle'); },
                setNetworkingGetStatus: function (connecting) { postStatus(connecting ? 'netbusy' : 'netidle'); },
                setNetworkingPostStatus: function (connecting) { postStatus(connecting ? 'netbusy' : 'netidle'); },
                setReceivingStatus: function () {},
                setEventName: function () {},
            },
            greg: gregImpl,
            // データ放送からのチャンネル切り替えは、検証では受け付けない。
            epg: {
                tune: function () { return false; },
            },
            // 双方向 (ネット接続)。Web 版の LiveDataBroadcastingManager と
            // 同じ形で、許可がオフのときは一切つながず、オンのときは
            // サーバー側の代理の口へ、アプリ内の中継を通してつなぐ。
            ip: {
                // Ethernet (DHCP)
                getConnectionType: function () { return 403; },
                isIPConnected: function () { return ipConfig.internetEnabled ? 1 : 0; },
                // 代理の口経由で HTTP GET し、応答をそのまま返す。
                // 失敗したときは Web 版と同じく何も返さない (空の応答)。
                get: async function (uri) {
                    if (!ipConfig.internetEnabled) {
                        return {};
                    }
                    var getURL = proxyURL('/api/data-broadcasting/request/' + uri);
                    if (getURL === null) {
                        return {};
                    }
                    try {
                        var getResponse = await fetch(getURL);
                        var getBody = await getResponse.arrayBuffer();
                        return {
                            statusCode: getResponse.status,
                            headers: getResponse.headers,
                            response: new Uint8Array(getBody),
                        };
                    } catch (e) {
                        return {};
                    }
                },
                // 代理の口経由で HTTP POST (フォーム形式の本文をそのまま) し、
                // 応答をそのまま返す。失敗したときは Web 版と同じ失敗の形。
                transmitTextDataOverIP: async function (uri, body) {
                    var failure = { resultCode: NaN, statusCode: '', response: new Uint8Array() };
                    if (!ipConfig.internetEnabled) {
                        return failure;
                    }
                    var postURL = proxyURL('/api/data-broadcasting/request/' + uri);
                    if (postURL === null) {
                        return failure;
                    }
                    try {
                        var postResponse = await fetch(postURL, {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                            body: body,
                        });
                        var postBody = await postResponse.arrayBuffer();
                        return {
                            resultCode: 1,
                            statusCode: String(postResponse.status),
                            response: new Uint8Array(postBody),
                        };
                    } catch (e) {
                        return failure;
                    }
                },
                // 代理の口経由で、接続できるかどうかをサーバー側で確かめる。
                confirmIPNetwork: async function (destination, isICMP, timeoutMillis) {
                    if (!ipConfig.internetEnabled) {
                        return null;
                    }
                    var query = 'destination=' + encodeURIComponent(destination)
                        + '&is_icmp=' + (isICMP ? 'true' : 'false')
                        + '&timeout_milliseconds=' + String(timeoutMillis);
                    var statusURL = proxyURL('/api/data-broadcasting/internet-status?' + query);
                    if (statusURL === null) {
                        return null;
                    }
                    try {
                        var statusResponse = await fetch(statusURL);
                        if (!statusResponse.ok) {
                            return null;
                        }
                        var data = await statusResponse.json();
                        return {
                            success: data.success,
                            ipAddress: data.ip_address,
                            responseTimeMillis: data.response_time_milliseconds,
                        };
                    } catch (e) {
                        return null;
                    }
                },
            },
            showErrorMessage: function () { postStatus('error'); },
        });

        // BML ブラウザが保持する FontFace をこの時点で全て明示的にロードしておき、画面のチラつきを防ぐ (Web 版と同じ)
        try {
            for (var i = 0; i < browser.fonts.length; i++) {
                browser.fonts[i].load();  // ロード完了を待たない
            }
        } catch (e) {
            // 先読みできなくても表示は続ける
        }

        browser.addEventListener('load', function (event) {
            bmlWidth = event.detail.resolution.width;
            bmlHeight = event.detail.resolution.height;
            if (container !== null) {
                container.style.setProperty('--bml-browser-width', bmlWidth + 'px');
                container.style.setProperty('--bml-browser-height', bmlHeight + 'px');
            }
            calculateScaleFactor();
            // 文書が開くたびに、映像の窓の切り抜きを入れ直す
            // (この時点で描く仕組み側の切り抜きは付き終わっている)。
            reapplyVideoPlaneClip(null);
            scheduleVideoPlaneClipReapply();
            postStatus('loaded');
        });

        // 映像の窓の場所や大きさが変わるたびに、切り抜きを入れ直す。
        // 四角は知らせに含まれるもの (body からの相対) を使う。
        browser.addEventListener('videochanged', function (event) {
            var rect = (event.detail && event.detail.clientRect) || null;
            reapplyVideoPlaneClip(rect);
            scheduleVideoPlaneClipReapply();
        });

        // BML ブラウザの表示状態が変化したとき (Web 版と同じく置き場ごと出し入れする)
        browser.addEventListener('invisible', function (event) {
            if (container !== null) {
                container.style.display = event.detail === true ? 'none' : 'block';
            }
            // データ放送が見えていない間は、字幕は映像全体に戻す。
            // また見えるようになったら、窓の場所を取り直して知らせる。
            if (event.detail === true) {
                postVideoRect(null);
            } else {
                reapplyVideoPlaneClip(null);
            }
        });

        decoder = createDecoder(config.serviceId, function (message) {
            // PMT から、データ放送がチャンネルに含まれているかどうかを知らせる
            // (Web 版と同じ判定: AdditionalAribBXMLInfo を含むコンポーネントが一つでもあるか)
            if (message.type === 'pmt') {
                var available = message.components.some(function (component) { return component.bxmlInfo !== undefined; });
                if (available !== availability) {
                    availability = available;
                    postStatus(available ? 'available' : 'unavailable');
                }
            }
            if (browser !== null) {
                browser.emitMessage(message);
            }
        }, function () {
            postStatus('error');
        });
        decoder.run(config.psiUrl);
    }

    async function stopInternal() {
        // 止めるときは、字幕を映像全体に戻す。
        lastVideoRect = null;
        postVideoRect(null);
        if (decoder !== null) {
            decoder.destroy();
            decoder = null;
        }
        if (browser !== null) {
            var target = browser;
            browser = null;
            try {
                await target.destroy();
            } catch (e) {
                // 破棄の失敗で止め直しが詰まらないようにする
            }
        }
        if (container !== null) {
            container.remove();
            container = null;
        }
    }

    function stop() {
        stopInternal();
    }

    // リモコンのボタンから、ARIB のキーコードをそのまま渡す。
    function sendKey(aribKeyCode) {
        if (browser !== null) {
            browser.content.processKeyDown(aribKeyCode);
            browser.content.processKeyUp(aribKeyCode);
        }
    }

    window.BMLSpike = {
        start: start,
        stop: stop,
        sendKey: sendKey,
    };
})();
