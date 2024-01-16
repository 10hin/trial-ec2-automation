# trial-ec2-automation

## progress

- [x] ImageBuilderパイプラインを作る
- [x] BuildしたAMIを稼働するAutoscaling Groupを作る
- [ ] Step Functionsによるビルド・デプロイのパイプライン(ステートマシン)を作成する
    - [x] ImageBuilder pipelineを実行する
    - [x] ImageBuilder pipelineの完了を待つ
    - [x] ImageBuilder pipelineが作成したLaunchTemplateの情報をSNS経由でユーザー通知(電子メール)する(publish SNS Lambda)
    - [x] ユーザー通知(電子メール)から応答として呼び出されるLambda(callback Lambda)を作成する(Lambda
    URL付き)
    - [x] SNS経由のユーザー通知にcallback Lambdaを呼び出して選択結果(ユーザー応答)をsfnパイプラインに通知するURLを含める(~~署名付きURL~~)
        - 署名付きURLは期限が5分程度と短いものしか作れず、今回のユースケースに合わないと判断した。
    - [x] ユーザー応答がリリース承諾だった場合に、ImageBuilder pipelineが作成した新しいLaunch TemplateのバージョンをDefaultに更新する
    - [x] Launch TemplateのDefaultバージョン更新後にAutoscaling Groupのインスタンス更新を開始する
