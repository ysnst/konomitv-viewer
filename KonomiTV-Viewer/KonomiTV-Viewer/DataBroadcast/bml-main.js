// データ放送の重ね合わせ検証用のつなぎ。
//
// Web 版 (KonomiTV クライアント) の作りをそのまま移したもの:
// - BML ブラウザの初期化は LiveDataBroadcastingManager.ts と同じ決め事。
//   ただし映像の要素は空の要素を渡し、中に何も入れない (映像の場所が
//   透明な穴として残り、下のネイティブ映像が見えるかを確かめるため)。
// - 材料 (PSI/SI アーカイブデータ) の解き方は、裏方
//   LivePSIArchivedDataDecoder.ts から番組情報を作る部分を除いて
//   書き写したもの。材料の口はアプリ内の中継経由の URL を Swift 側から
//   渡してもらう。
// - 双方向 (ネット接続) は無効の申告 (接続していない) にしてある。
// - 状態 (読み込み中・データ放送の有無・失敗) は Swift 側へ知らせ、
//   表示はアプリ側の知らせ表示に任せる。
//
// Swift 側からの入口は window.BMLSpike の3つ:
//   start({ psiUrl, serviceId }) / stop() / sendKey(aribKeyCode)

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
    // (Web 版は無言だが、検証では失敗が見えた方が確かめやすいため)。
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
                    // それ以外の接続の失敗は、検証で見えるよう知らせる。
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
                setUrl: function () {},
                setNetworkingGetStatus: function () {},
                setNetworkingPostStatus: function () {},
                setReceivingStatus: function () {},
                setEventName: function () {},
            },
            greg: gregImpl,
            // データ放送からのチャンネル切り替えは、検証では受け付けない。
            epg: {
                tune: function () { return false; },
            },
            // 双方向 (ネット接続) は無効の申告 (接続していない)。
            ip: {
                getConnectionType: function () { return 403; },
                isIPConnected: function () { return 0; },
                get: async function () { return {}; },
                transmitTextDataOverIP: async function () {
                    return { resultCode: NaN, statusCode: '', response: new Uint8Array() };
                },
                confirmIPNetwork: async function () { return null; },
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
