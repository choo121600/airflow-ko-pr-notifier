# airflow-ko-pr-notifier

apache/airflow 저장소에 `translation:ko` 라벨이 붙은 새 PR이 올라오면 Discord 웹훅으로 알림을 보냅니다.

## 동작 방식

- GitHub Actions가 15분마다 (`*/15 * * * *`) GitHub Search API로
  `repo:apache/airflow is:pr label:"translation:ko"` PR 중 마지막 확인 시각 이후 생성된 것을 조회합니다.
- 새 PR마다 Discord 웹훅으로 embed 메시지를 하나씩 전송합니다.
- 마지막 확인 시각과 이미 알린 PR 번호는 `state.json`에 기록되어 중복 알림을 방지합니다.

## 설정

Discord 웹훅 URL을 repo secret으로 등록해야 합니다:

```sh
gh secret set DISCORD_WEBHOOK_URL -R choo121600/airflow-ko-pr-notifier
```

수동 실행으로 테스트:

```sh
gh workflow run notify.yml -R choo121600/airflow-ko-pr-notifier
```

> 참고: GitHub Actions의 schedule cron은 부하에 따라 수 분 지연될 수 있습니다.
> 또한 60일간 레포에 활동이 없으면 scheduled workflow가 자동 비활성화되는데,
> 이 워크플로는 새 PR을 발견할 때마다 `state.json`을 커밋하므로 평소엔 해당되지 않습니다.
